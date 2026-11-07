package export

import (
	"bufio"
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"os"
	"path/filepath"
	"strings"
	"time"
)

// writeAtomic writes data through a temporary file and a rename, so a reader never sees half a file.
func writeAtomic(path string, data []byte) error {
	return replace(path, time.Time{}, func(w io.Writer) error {
		_, err := w.Write(data)
		return err
	})
}

// replace fills a temporary file next to path and renames it to path. A zero mtime keeps the time of the write.
func replace(path string, mtime time.Time, fill func(io.Writer) error) (err error) {
	dir := filepath.Dir(path)
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return err
	}
	tmp, err := os.CreateTemp(dir, ".memories-*.tmp")
	if err != nil {
		return err
	}
	defer func() {
		if err != nil {
			_ = os.Remove(tmp.Name())
		}
	}()
	if err := fill(tmp); err != nil {
		_ = tmp.Close()
		return err
	}
	if err := tmp.Close(); err != nil {
		return err
	}
	if err := os.Chmod(tmp.Name(), 0o644); err != nil {
		return err
	}
	if !mtime.IsZero() {
		if err := os.Chtimes(tmp.Name(), mtime, mtime); err != nil {
			return err
		}
	}
	return os.Rename(tmp.Name(), path)
}

// copyFile copies a regular file to dst unless dst exists, and keeps its modification time. It opens src only for
// reading, and refuses a source that is a link or not a regular file.
func copyFile(src, dst string) (bool, error) {
	if _, err := os.Lstat(dst); err == nil {
		return false, nil
	} else if !errors.Is(err, fs.ErrNotExist) {
		return false, err
	}
	info, err := os.Lstat(src)
	if err != nil {
		return false, err
	}
	if !info.Mode().IsRegular() {
		return false, fmt.Errorf("%s is not a regular file", src)
	}
	in, err := os.Open(src)
	if err != nil {
		return false, err
	}
	defer func() { _ = in.Close() }()
	err = replace(dst, info.ModTime(), func(w io.Writer) error {
		_, err := io.Copy(w, in)
		return err
	})
	return err == nil, err
}

func marshal(v any, indent string) ([]byte, error) {
	var buf bytes.Buffer
	enc := json.NewEncoder(&buf)
	enc.SetEscapeHTML(false)
	enc.SetIndent("", indent)
	if err := enc.Encode(v); err != nil {
		return nil, err
	}
	return buf.Bytes(), nil
}

func marshalLine(v any) ([]byte, error) { return marshal(v, "") }

func marshalIndent(v any) ([]byte, error) { return marshal(v, " ") }

func writeJSONL[T any](path string, rows []T) error {
	var buf bytes.Buffer
	for _, r := range rows {
		b, err := marshalLine(r)
		if err != nil {
			return err
		}
		buf.Write(b)
	}
	return writeAtomic(path, buf.Bytes())
}

// readJSONL reads the rows of an earlier run. A missing file has no rows. Numbers stay exact.
func readJSONL[T any](path string) ([]T, error) {
	f, err := os.Open(path)
	if errors.Is(err, fs.ErrNotExist) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	defer func() { _ = f.Close() }()
	var rows []T
	sc := bufio.NewScanner(f)
	sc.Buffer(make([]byte, 64*1024), 64<<20)
	for n := 1; sc.Scan(); n++ {
		line := strings.TrimSpace(sc.Text())
		if line == "" {
			continue
		}
		var row T
		dec := json.NewDecoder(strings.NewReader(line))
		dec.UseNumber()
		if err := dec.Decode(&row); err != nil {
			return nil, fmt.Errorf("%s line %d: %w", path, n, err)
		}
		rows = append(rows, row)
	}
	if err := sc.Err(); err != nil {
		return nil, fmt.Errorf("%s: %w", path, err)
	}
	return rows, nil
}

// readJSON reads a JSON object of an earlier run. A missing file gives nil.
func readJSON(path string) (map[string]any, error) {
	b, err := os.ReadFile(path)
	if errors.Is(err, fs.ErrNotExist) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	var out map[string]any
	dec := json.NewDecoder(bytes.NewReader(b))
	dec.UseNumber()
	if err := dec.Decode(&out); err != nil {
		return nil, fmt.Errorf("%s: %w", path, err)
	}
	return out, nil
}

// inside reports whether path is dir or below it, after links in the existing part of both are resolved. It ignores
// case, since the game runs on file systems where "wtf" and "WTF" are one folder.
func inside(path, dir string) bool {
	p, d := strings.ToLower(resolve(path)), strings.ToLower(resolve(dir))
	rel, err := filepath.Rel(d, p)
	return err == nil && rel != ".." && !strings.HasPrefix(rel, ".."+string(filepath.Separator))
}

func resolve(path string) string {
	path = filepath.Clean(path)
	var rest []string
	for {
		if r, err := filepath.EvalSymlinks(path); err == nil {
			return filepath.Join(append([]string{r}, rest...)...)
		}
		parent := filepath.Dir(path)
		if parent == path {
			return filepath.Join(append([]string{path}, rest...)...)
		}
		rest = append([]string{filepath.Base(path)}, rest...)
		path = parent
	}
}
