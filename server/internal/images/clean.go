// Package images re-encodes uploaded screenshots, so that the server stores only pixels: no EXIF location data,
// no text chunks, no trailing bytes and no file that is secretly another format.
package images

import (
	"bytes"
	"errors"
	"image"
	"image/color"
	"image/jpeg"
	"image/png"
	"io"
	"strings"
)

var (
	// ErrUnsupported means that the bytes are not a JPEG or PNG that matches the file extension, that they use a
	// colour model or a scan count that heavy refuses, or that they are damaged.
	ErrUnsupported = errors.New("images: not a JPEG or PNG image that matches the file name")
	// ErrTooManyPixels means that the image is larger than the pixel limit.
	ErrTooManyPixels = errors.New("images: the image has too many pixels")
)

const jpegQuality = 90

// maxProgressiveScans is the most scans that a progressive JPEG may hold. Each scan walks every block of the image,
// even an empty one, so a small file of many scans costs minutes of CPU. Progressive encoders write about 10. A
// sequential JPEG codes each component in one scan, and each of its scans also runs the inverse DCT of every block
// it covers, so its scans may name each component only once in all.
const maxProgressiveScans = 32

// heavy reports whether a decode costs more memory or CPU than the pixel limit allows for. A CMYK or RGB JPEG
// converts its planes into a second image (up to 24 bytes per pixel when progressive), and a 16-bit PNG takes 8 bytes
// per pixel, twice that when interlaced. The game writes none of them. What is left costs at most 15 bytes per pixel:
// a progressive 4:4:4 YCbCr JPEG.
func heavy(format string, m color.Model, raw []byte) bool {
	if format == "jpeg" {
		return m != color.YCbCrModel && m != color.GrayModel || heavyJPEG(raw, m == color.YCbCrModel)
	}
	return m == color.RGBA64Model || m == color.NRGBA64Model || m == color.Gray16Model
}

// heavyJPEG reports whether the JPEG has more scans than its frame allows, or a segment that turns its YCbCr into
// RGB at the end of the decode: a frame header with the component IDs R, G and B, or an Adobe APP14 segment with
// transform 0. A later APP0 can undo the JFIF segment that hides the IDs from DecodeConfig, and the decoder honours
// an APP14 segment wherever it sits, so the whole file is searched for it. The entropy-coded data never holds 0xFF
// followed by one of these marker bytes, so a match is a segment, or bytes inside the payload of another one, which
// only refuses a file. The RGB segments matter only when colour is true: the decoder ignores them for a grey frame,
// which Adobe tools tag with transform 0.
func heavyJPEG(raw []byte, colour bool) bool {
	at, marker := frame(raw)
	// The frame header: precision, height, width, the count, then 3 bytes for each component, ID first.
	if at < 0 || len(raw)-at < 6 {
		return true
	}
	sof := raw[at:]
	nComp := int(sof[5])
	if colour && nComp == 3 && len(sof) >= 13 && sof[6] == 'R' && sof[9] == 'G' && sof[12] == 'B' {
		return true
	}
	maxScans := nComp
	if marker == 0xc2 {
		maxScans = maxProgressiveScans
	}
	scans := 0
	for i := 0; ; {
		j := bytes.IndexByte(raw[i:], 0xff)
		if j < 0 || i+j+1 >= len(raw) {
			return false
		}
		i += j + 1
		seg := raw[i+1:]
		switch raw[i] {
		case 0xda: // SOS: a scan needs a frame first, so only the ones after the frame header count.
			if i > at {
				// A sequential scan costs one pass for each of its components, the count after the length.
				n := 1
				if marker != 0xc2 && len(seg) >= 3 {
					n = max(1, int(seg[2]))
				}
				if scans += n; scans > maxScans {
					return true
				}
			}
		case 0xee: // APP14: a 2-byte length, "Adobe", then the transform byte 11 bytes later; 0 means RGB.
			if colour && len(seg) >= 14 && bytes.Equal(seg[2:7], []byte("Adobe")) && seg[13] == 0 {
				return true
			}
		}
	}
}

// frame walks the segments of the JPEG the way image/jpeg does, and returns the offset of the body of the frame
// header that the decoder reads, after its length, and the SOF marker. Only segments with a length come before the
// frame, and the decoder refuses a second frame header, so this is the frame of the decode. at is -1 when the walk
// finds none.
func frame(raw []byte) (at int, marker byte) {
	for i := 2; ; {
		if i+2 > len(raw) {
			return -1, 0
		}
		t0, t1 := raw[i], raw[i+1]
		i += 2
		for t0 != 0xff {
			if i >= len(raw) {
				return -1, 0
			}
			t0, t1 = t1, raw[i]
			i++
		}
		m := t1
		if m == 0 {
			continue
		}
		for m == 0xff {
			if i >= len(raw) {
				return -1, 0
			}
			m = raw[i]
			i++
		}
		if m == 0xd9 || m == 0xda {
			return -1, 0
		}
		if m >= 0xd0 && m <= 0xd7 {
			continue
		}
		if i+2 > len(raw) {
			return -1, 0
		}
		n := int(raw[i])<<8 | int(raw[i+1])
		i += 2
		if n < 2 {
			return -1, 0
		}
		if m == 0xc0 || m == 0xc1 || m == 0xc2 {
			return i, m
		}
		i += n - 2
	}
}

// Supported reports whether ext, the extension of a file name, is one that Clean takes.
func Supported(ext string) bool {
	_, ok := formatOf(ext)
	return ok
}

func formatOf(ext string) (string, bool) {
	switch strings.ToLower(strings.TrimPrefix(ext, ".")) {
	case "jpg":
		return "jpeg", true
	case "png":
		return "png", true
	}
	return "", false
}

// Clean decodes the image and encodes it again in the same format. ext is the extension of the file name, ".jpg"
// or ".png". The format of the content must match it. The size is read from the header and checked before the
// decode, so a small file that claims a huge size costs no memory. The caller bounds the size of raw.
func Clean(raw []byte, ext string, maxPixels int64) ([]byte, error) {
	want, ok := formatOf(ext)
	if !ok {
		return nil, ErrUnsupported
	}
	decodeConfig, decode, encode := png.DecodeConfig, png.Decode, png.Encode
	if want == "jpeg" {
		decodeConfig, decode = jpeg.DecodeConfig, jpeg.Decode
		encode = func(w io.Writer, m image.Image) error {
			return jpeg.Encode(w, m, &jpeg.Options{Quality: jpegQuality})
		}
	}
	cfg, err := decodeConfig(bytes.NewReader(raw))
	if err != nil || cfg.Width < 1 || cfg.Height < 1 {
		return nil, ErrUnsupported
	}
	// Both sides are below 2^31 here, so the product fits in an int64.
	if int64(cfg.Width)*int64(cfg.Height) > maxPixels {
		return nil, ErrTooManyPixels
	}
	if heavy(want, cfg.ColorModel, raw) {
		return nil, ErrUnsupported
	}
	img, err := decode(bytes.NewReader(raw))
	if err != nil {
		return nil, ErrUnsupported
	}

	var out bytes.Buffer
	out.Grow(len(raw))
	if err := encode(&out, img); err != nil {
		return nil, err
	}
	return out.Bytes(), nil
}
