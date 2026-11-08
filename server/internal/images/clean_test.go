package images

import (
	"bytes"
	"errors"
	"image"
	"image/color"
	"image/jpeg"
	"image/png"
	"os"
	"path/filepath"
	"testing"
)

const maxPixels = 50_000_000

func testdata(t testing.TB, name string) []byte {
	t.Helper()
	b, err := os.ReadFile(filepath.Join("testdata", name))
	if err != nil {
		t.Fatal(err)
	}
	return b
}

func TestCleanReencodesEachFormat(t *testing.T) {
	for _, tc := range []struct{ file, ext, format string }{
		{"small.jpg", ".jpg", "jpeg"},
		{"small.png", ".png", "png"},
		{"small.jpg", ".JPG", "jpeg"},
		{"small.png", "png", "png"},
	} {
		out, err := Clean(testdata(t, tc.file), tc.ext, maxPixels)
		if err != nil {
			t.Fatalf("%s: %v", tc.file, err)
		}
		cfg, format, err := image.DecodeConfig(bytes.NewReader(out))
		if err != nil || format != tc.format || cfg.Width != 16 || cfg.Height != 8 {
			t.Errorf("%s: output is %v %dx%d, %v", tc.file, format, cfg.Width, cfg.Height, err)
		}
	}
}

func TestCleanKeepsThePixelsOfAPNG(t *testing.T) {
	src := testdata(t, "small.png")
	out, err := Clean(src, ".png", maxPixels)
	if err != nil {
		t.Fatal(err)
	}
	a, err := png.Decode(bytes.NewReader(src))
	if err != nil {
		t.Fatal(err)
	}
	b, err := png.Decode(bytes.NewReader(out))
	if err != nil {
		t.Fatal(err)
	}
	if a.Bounds() != b.Bounds() {
		t.Fatalf("bounds %v, want %v", b.Bounds(), a.Bounds())
	}
	r := a.Bounds()
	for y := r.Min.Y; y < r.Max.Y; y++ {
		for x := r.Min.X; x < r.Max.X; x++ {
			if a.At(x, y) != b.At(x, y) {
				t.Fatalf("pixel %d,%d changed", x, y)
			}
		}
	}
}

func TestCleanRemovesExifLocationData(t *testing.T) {
	src := testdata(t, "exif-gps.jpg")
	if !bytes.Contains(src, []byte("Exif\x00\x00")) {
		t.Fatal("the test file has no EXIF marker, so the test proves nothing")
	}
	if _, err := jpeg.Decode(bytes.NewReader(src)); err != nil {
		t.Fatalf("the test file must be a valid JPEG: %v", err)
	}
	out, err := Clean(src, ".jpg", maxPixels)
	if err != nil {
		t.Fatal(err)
	}
	if bytes.Contains(out, []byte("Exif")) || bytes.Contains(out, []byte{0xFF, 0xE1}) {
		t.Error("the clean file still has an EXIF segment")
	}
}

func TestCleanRemovesPNGTextChunks(t *testing.T) {
	src := testdata(t, "text-chunk.png")
	if !bytes.Contains(src, []byte("secret-note")) {
		t.Fatal("the test file has no text chunk, so the test proves nothing")
	}
	out, err := Clean(src, ".png", maxPixels)
	if err != nil {
		t.Fatal(err)
	}
	if bytes.Contains(out, []byte("tEXt")) || bytes.Contains(out, []byte("secret-note")) {
		t.Error("the clean file still has the text chunk")
	}
}

func TestCleanDropsTrailingBytes(t *testing.T) {
	src := append(testdata(t, "small.png"), []byte("<script>trailing payload</script>")...)
	out, err := Clean(src, ".png", maxPixels)
	if err != nil {
		t.Fatal(err)
	}
	if bytes.Contains(out, []byte("payload")) {
		t.Error("the trailing bytes survived")
	}
}

func TestCleanRejectsAPNGBombFromItsHeader(t *testing.T) {
	_, err := Clean(testdata(t, "bomb.png"), ".png", maxPixels)
	if !errors.Is(err, ErrTooManyPixels) {
		t.Fatalf("err = %v, want ErrTooManyPixels (a decode would give ErrUnsupported, as the file has no pixel data)", err)
	}
}

func TestCleanPixelLimitIsExact(t *testing.T) {
	src := testdata(t, "small.png") // 16 x 8 = 128 pixels
	if _, err := Clean(src, ".png", 128); err != nil {
		t.Errorf("at the limit: %v", err)
	}
	if _, err := Clean(src, ".png", 127); !errors.Is(err, ErrTooManyPixels) {
		t.Errorf("over the limit: %v", err)
	}
}

func TestCleanRejectsWhatIsNotAMatchingImage(t *testing.T) {
	for _, tc := range []struct {
		name string
		data []byte
		ext  string
	}{
		{"tga", testdata(t, "small.tga"), ".tga"},
		{"tga as jpg", testdata(t, "small.tga"), ".jpg"},
		{"jpeg named png", testdata(t, "jpeg-named.png"), ".png"},
		{"png named jpg", testdata(t, "small.png"), ".jpg"},
		{"truncated jpeg", testdata(t, "small.jpg")[:300], ".jpg"},
		{"truncated png", testdata(t, "small.png")[:60], ".png"},
		{"header only jpeg", testdata(t, "small.jpg")[:2], ".jpg"},
		{"empty", nil, ".jpg"},
		{"text", []byte("not an image at all"), ".png"},
		{"unknown extension", testdata(t, "small.jpg"), ".gif"},
		{"no extension", testdata(t, "small.jpg"), ""},
		{"cmyk jpeg", testdata(t, "cmyk.jpg"), ".jpg"},
		{"16-bit png", testdata(t, "deep.png"), ".png"},
	} {
		if _, err := Clean(tc.data, tc.ext, maxPixels); !errors.Is(err, ErrUnsupported) {
			t.Errorf("%s: err = %v, want ErrUnsupported", tc.name, err)
		}
	}
}

func FuzzClean(f *testing.F) {
	for _, n := range []string{"small.jpg", "small.png", "exif-gps.jpg", "bomb.png", "small.tga"} {
		f.Add(testdata(f, n))
	}
	f.Fuzz(func(t *testing.T, b []byte) {
		for _, ext := range []string{".jpg", ".png"} {
			out, err := Clean(b, ext, 1_000_000)
			if err != nil {
				continue
			}
			in, _, _ := image.DecodeConfig(bytes.NewReader(b))
			cfg, format, err := image.DecodeConfig(bytes.NewReader(out))
			want, _ := formatOf(ext)
			if err != nil || format != want || cfg.Width != in.Width || cfg.Height != in.Height {
				t.Fatalf("%s: output is %v %dx%d (%v), input is %dx%d", ext, format, cfg.Width, cfg.Height, err, in.Width, in.Height)
			}
		}
	})
}

// An Adobe segment after the scan turns a YCbCr JPEG into RGB at the end of the decode, where DecodeConfig no longer
// looks, so the check must see it anyway.
func TestCleanRejectsALateAdobeRGBSegment(t *testing.T) {
	raw := baselineJPEG(t)
	eoi := len(raw) - 2
	app14 := []byte{0xff, 0xee, 0, 14, 'A', 'd', 'o', 'b', 'e', 0, 100, 0, 0, 0, 0, 0}
	late := append(append(append([]byte{}, raw[:eoi]...), app14...), raw[eoi:]...)
	if img, err := jpeg.Decode(bytes.NewReader(late)); err != nil {
		t.Fatalf("the file must decode, or the test proves nothing: %v", err)
	} else if _, ok := img.(*image.RGBA); !ok {
		t.Fatalf("the decode gives %T, want *image.RGBA, or the test proves nothing", img)
	}
	if _, err := Clean(late, ".jpg", maxPixels); !errors.Is(err, ErrUnsupported) {
		t.Errorf("a late Adobe RGB segment: err = %v, want ErrUnsupported", err)
	}
}

// The decoder ignores the Adobe transform of a grey frame, so a grey JPEG from an Adobe tool stays cheap.
func TestCleanTakesAGreyJPEGWithAnAdobeSegment(t *testing.T) {
	var buf bytes.Buffer
	if err := jpeg.Encode(&buf, image.NewGray(image.Rect(0, 0, 16, 8)), nil); err != nil {
		t.Fatal(err)
	}
	raw := buf.Bytes()
	app14 := []byte{0xff, 0xee, 0, 14, 'A', 'd', 'o', 'b', 'e', 0, 100, 0, 0, 0, 0, 0}
	tagged := append(append(append([]byte{}, raw[:2]...), app14...), raw[2:]...)
	if _, err := Clean(tagged, ".jpg", maxPixels); err != nil {
		t.Errorf("a grey JPEG with Adobe transform 0: %v", err)
	}
}

func baselineJPEG(t *testing.T) []byte {
	t.Helper()
	var buf bytes.Buffer
	if err := jpeg.Encode(&buf, image.NewYCbCr(image.Rect(0, 0, 16, 8), image.YCbCrSubsampleRatio444), nil); err != nil {
		t.Fatal(err)
	}
	if _, err := Clean(buf.Bytes(), ".jpg", maxPixels); err != nil {
		t.Fatalf("the plain JPEG: %v", err)
	}
	return buf.Bytes()
}

// progressiveJPEG builds a progressive JPEG whose scans are AC refinements that one EOB-run code covers. With rgb,
// it has 3 components with the IDs R, G and B, hidden from DecodeConfig by a JFIF segment, which a later APP0
// undoes in the decode.
func progressiveJPEG(scans int, rgb bool) []byte {
	const side = 64
	var b bytes.Buffer
	b.Write([]byte{0xff, 0xd8})
	if rgb {
		b.Write([]byte{0xff, 0xe0, 0, 16, 'J', 'F', 'I', 'F', 0, 1, 1, 0, 0, 1, 0, 1, 0, 0})
	}
	b.Write([]byte{0xff, 0xdb, 0, 67, 0})
	b.Write(bytes.Repeat([]byte{1}, 64))
	ids := []byte{1}
	if rgb {
		ids = []byte("RGB")
	}
	b.Write([]byte{0xff, 0xc2, 0, byte(8 + 3*len(ids)), 8, 0, side, 0, side, byte(len(ids))})
	for _, id := range ids {
		b.Write([]byte{id, 0x11, 0})
	}
	if rgb {
		b.Write([]byte{0xff, 0xe0, 0, 7, 'X', 'X', 'X', 'X', 'X'})
	}
	// AC table 0 has one code of length 1 for the symbol 0xE0: an EOB run of 2^14 plus 14 bits, which covers every
	// block. The entropy data is that code with its 14 bits set.
	b.Write([]byte{0xff, 0xc4, 0, 20, 0x10, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0xe0})
	for i := range scans {
		b.Write([]byte{0xff, 0xda, 0, 8, 1, ids[i%len(ids)], 0, 1, 63, 0x10, 0x7f, 0xfe})
	}
	b.Write([]byte{0xff, 0xd9})
	return b.Bytes()
}

// Each scan walks every block of the image, so a file of many tiny scans is a CPU bomb.
func TestCleanRejectsAProgressiveJPEGWithTooManyScans(t *testing.T) {
	if _, err := Clean(progressiveJPEG(maxProgressiveScans, false), ".jpg", maxPixels); err != nil {
		t.Fatalf("%d scans: %v", maxProgressiveScans, err)
	}
	if _, err := Clean(progressiveJPEG(maxProgressiveScans+1, false), ".jpg", maxPixels); !errors.Is(err, ErrUnsupported) {
		t.Errorf("%d scans: err = %v, want ErrUnsupported", maxProgressiveScans+1, err)
	}
}

func TestCleanRejectsRGBComponentIDsBehindJFIF(t *testing.T) {
	raw := progressiveJPEG(3, true)
	if cfg, _, err := image.DecodeConfig(bytes.NewReader(raw)); err != nil || cfg.ColorModel != color.YCbCrModel {
		t.Fatalf("DecodeConfig must see YCbCr, or the test proves nothing: %v", err)
	}
	if img, err := jpeg.Decode(bytes.NewReader(raw)); err != nil {
		t.Fatalf("the file must decode, or the test proves nothing: %v", err)
	} else if _, ok := img.(*image.RGBA); !ok {
		t.Fatalf("the decode gives %T, want *image.RGBA, or the test proves nothing", img)
	}
	if _, err := Clean(raw, ".jpg", maxPixels); !errors.Is(err, ErrUnsupported) {
		t.Errorf("err = %v, want ErrUnsupported", err)
	}
}

// Each scan of a sequential JPEG runs the inverse DCT of every block, so it may scan each component only once.
func TestCleanRejectsASequentialJPEGThatScansAComponentTwice(t *testing.T) {
	raw := baselineJPEG(t)
	sos := bytes.Index(raw, []byte{0xff, 0xda})
	eoi := len(raw) - 2
	twice := append(append(append([]byte{}, raw[:eoi]...), raw[sos:eoi]...), raw[eoi:]...)
	if _, err := jpeg.Decode(bytes.NewReader(twice)); err != nil {
		t.Fatalf("the file must decode, or the test proves nothing: %v", err)
	}
	if _, err := Clean(twice, ".jpg", maxPixels); !errors.Is(err, ErrUnsupported) {
		t.Errorf("err = %v, want ErrUnsupported", err)
	}
}

// The scans of an EXIF thumbnail sit before the frame header of the image, so they do not count.
func TestCleanTakesASequentialJPEGWithAThumbnail(t *testing.T) {
	raw := baselineJPEG(t)
	thumb := append([]byte("Exif\x00\x00"), raw...)
	app1 := append([]byte{0xff, 0xe1, byte((len(thumb) + 2) >> 8), byte(len(thumb) + 2)}, thumb...)
	with := append(append(append([]byte{}, raw[:2]...), app1...), raw[2:]...)
	if _, err := Clean(with, ".jpg", maxPixels); err != nil {
		t.Errorf("err = %v", err)
	}
}

func TestFrameWalksSegmentsLikeTheDecoder(t *testing.T) {
	sof := []byte{0xff, 0xc2, 0, 11, 8, 0, 1, 0, 1, 1, 1, 0x11, 0}
	sequential := []byte{0xff, 0xc0, 0, 11, 8, 0, 1, 0, 1, 1, 1, 0x11, 0}
	for _, tc := range []struct {
		name   string
		raw    []byte
		at     int
		marker byte
	}{
		{"frame first", append([]byte{0xff, 0xd8}, sof...), 6, 0xc2},
		{"sequential frame", append([]byte{0xff, 0xd8}, sequential...), 6, 0xc0},
		{"after a segment", append([]byte{0xff, 0xd8, 0xff, 0xfe, 0, 3, 'x'}, sof...), 11, 0xc2},
		{"after junk, stuffing, fill and a restart", append([]byte{0xff, 0xd8, 1, 2, 0xff, 0, 0xff, 0xd0, 0xff}, sof...), 13, 0xc2},
		{"end of image first", []byte{0xff, 0xd8, 0xff, 0xd9}, -1, 0},
		{"scan first", []byte{0xff, 0xd8, 0xff, 0xda, 0, 8}, -1, 0},
		{"short length", []byte{0xff, 0xd8, 0xff, 0xfe, 0, 1, 0xff, 0xc0}, -1, 0},
		{"cut in the marker", []byte{0xff, 0xd8, 0xff}, -1, 0},
		{"cut in the junk", []byte{0xff, 0xd8, 1, 2, 3}, -1, 0},
		{"cut in the fill", []byte{0xff, 0xd8, 0xff, 0xff}, -1, 0},
		{"cut in the length", []byte{0xff, 0xd8, 0xff, 0xfe, 0}, -1, 0},
		{"cut after a segment", []byte{0xff, 0xd8, 0xff, 0xfe, 0, 3, 'x'}, -1, 0},
	} {
		if at, marker := frame(tc.raw); at != tc.at || marker != tc.marker {
			t.Errorf("%s: frame = %d, %#x, want %d, %#x", tc.name, at, marker, tc.at, tc.marker)
		}
	}
	if !heavyJPEG([]byte{0xff, 0xd8, 0xff, 0xd9}, true) {
		t.Error("a JPEG with no frame must count as heavy")
	}
}
