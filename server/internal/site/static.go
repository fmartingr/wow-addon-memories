package site

import (
	"net/http"
	"os"
	"path"
	"strings"
)

// Content types of the files that the disk handlers serve. A file with any other extension gives 404.
var (
	MapTypes  = map[string]string{".webp": "image/webp", ".jpg": "image/jpeg", ".js": "text/javascript; charset=utf-8"}
	FontTypes = map[string]string{".woff2": "font/woff2", ".txt": "text/plain; charset=utf-8"}
)

const staticCacheControl = "public, max-age=86400"

// NewStatic serves the files of dir under the prefix of the request path, which is the part before the file path
// (for example "/_/map/"). It gives a plain 404 for a path that ends in "/", a path with a segment that starts with
// ".", and an extension that is not a key of types. A missing dir is not an error: every request then gives 404.
func NewStatic(prefix, dir string, types map[string]string) http.Handler {
	files := http.FileServerFS(os.DirFS(dir))
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodGet && r.Method != http.MethodHead {
			http.NotFound(w, r)
			return
		}
		rel, ok := strings.CutPrefix(r.URL.Path, prefix)
		if !ok || rel == "" || strings.HasSuffix(rel, "/") || path.Clean("/"+rel) != "/"+rel {
			http.NotFound(w, r)
			return
		}
		for seg := range strings.SplitSeq(rel, "/") {
			if strings.HasPrefix(seg, ".") {
				http.NotFound(w, r)
				return
			}
		}
		ct, ok := types[strings.ToLower(path.Ext(rel))]
		if !ok {
			http.NotFound(w, r)
			return
		}
		h := w.Header()
		h.Set("Content-Type", ct)
		h.Set("Cache-Control", staticCacheControl)
		r2 := r.Clone(r.Context())
		r2.URL.Path = "/" + rel
		files.ServeHTTP(&errorHeaders{ResponseWriter: w}, r2)
	})
}

// errorHeaders drops the file headers from an error response, so that a 404 does not keep the content type and the
// cache header of a file.
type errorHeaders struct{ http.ResponseWriter }

func (w *errorHeaders) WriteHeader(status int) {
	if status >= 400 {
		h := w.Header()
		h.Del("Content-Type")
		h.Del("Cache-Control")
		h.Del("Last-Modified")
	}
	w.ResponseWriter.WriteHeader(status)
}
