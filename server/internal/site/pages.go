package site

import (
	"bytes"
	"cmp"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"html"
	"io"
	"io/fs"
	"log/slog"
	"net/http"
	"os"
	"path"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/fmartingr/wow-addon-memories/server/internal/ids"
	"github.com/fmartingr/wow-addon-memories/server/internal/store"
)

// ClaimFinder looks up the owner record of a character path. *store.Store satisfies it.
type ClaimFinder interface {
	ClaimByPath(ctx context.Context, flavor, region, realm, name string) (store.Claim, error)
}

const (
	entryAttr        = ` data-entry="data/entry.json"`
	robotsNoIndex    = "noindex, nofollow"
	maxCharacterFile = 8 << 20
	maxCachedETags   = 8192
)

var (
	bodyTag  = regexp.MustCompile(`(?i)<body(\s[^>]*)?>`)
	titleTag = regexp.MustCompile(`(?is)<title>(.*?)</title>`)
	shotName = regexp.MustCompile(`^WoWScrnShot_[0-9]{6}_[0-9]{6}\.(jpg|png)$`)
)

// dataTypes lists the files of a character that the data route serves, with their content types.
var dataTypes = map[string]string{
	"entry.json":     "application/json",
	"character.json": "application/json",
	"journey.jsonl":  "application/x-ndjson",
	"trail.jsonl":    "application/x-ndjson",
}

// viewerTypes are the extensions of the viewer code files that NewPages keeps in memory, with their content types.
var viewerTypes = map[string]string{
	".mjs": "text/javascript; charset=utf-8",
	".js":  "text/javascript; charset=utf-8",
	".css": "text/css; charset=utf-8",
	".png": "image/png",
}

// viewerSkipDirs are the folders of MEMORIES_WEB_DIR that are not code files. map and fonts come from the disk, test
// is not part of the viewer, and characters is an old link to local data.
var viewerSkipDirs = map[string]bool{"map": true, "fonts": true, "test": true, "characters": true}

// maxViewerBytes caps the viewer code files in memory, so that a wrong MEMORIES_WEB_DIR cannot load a large tree.
const maxViewerBytes = 8 << 20

// AssetPrefix is the URL prefix of every viewer file. A flavor never starts with "_", so it cannot match a character.
const AssetPrefix = "/_/"

type asset struct {
	body        []byte
	contentType string
	etag        string
}

// Pages serves the viewer assets, the character pages and the data files of the characters.
type Pages struct {
	webDir   string
	assets   map[string]asset
	index    []byte
	titleAt  [2]int // the text between <title> and </title> of index
	attrAt   int    // where the data-entry attribute goes: right after "<body"
	claims   ClaimFinder
	blobs    store.Blobs
	notFound http.Handler
	log      *slog.Logger
	etags    etagCache
	titles   etagCache
}

// NewPages reads the viewer files of webDir once. It fails when index.html has no <title> before its <body> tag,
// because the character pages are made from those two places.
func NewPages(webDir string, claims ClaimFinder, blobs store.Blobs, notFound http.Handler, log *slog.Logger) (*Pages, error) {
	read := func(name string) ([]byte, error) {
		b, err := os.ReadFile(filepath.Join(webDir, name))
		if err != nil {
			return nil, fmt.Errorf("could not read the viewer file %s: %w. Check MEMORIES_WEB_DIR", name, err)
		}
		return b, nil
	}
	p := &Pages{
		webDir: webDir, assets: map[string]asset{}, claims: claims, blobs: blobs, notFound: notFound, log: log,
		etags: etagCache{m: map[etagKey]string{}}, titles: etagCache{m: map[etagKey]string{}},
	}
	var err error
	if p.index, err = read("index.html"); err != nil {
		return nil, err
	}
	body := bodyTag.FindIndex(p.index)
	title := titleTag.FindSubmatchIndex(p.index)
	if body == nil || title == nil || title[3] > body[0] {
		return nil, fmt.Errorf("the viewer file %s needs a <title> element before its <body> tag. Check MEMORIES_WEB_DIR",
			filepath.Join(webDir, "index.html"))
	}
	p.titleAt = [2]int{title[2], title[3]}
	p.attrAt = body[0] + len("<body")
	return p, p.loadAssets(read)
}

// loadAssets reads each viewer code file of the web folder into memory.
func (p *Pages) loadAssets(read func(string) ([]byte, error)) error {
	total := 0
	return fs.WalkDir(os.DirFS(p.webDir), ".", func(rel string, d fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		name := d.Name()
		if rel != "." && (strings.HasPrefix(name, ".") || (d.IsDir() && rel == name && viewerSkipDirs[name])) {
			if d.IsDir() {
				return fs.SkipDir
			}
			return nil
		}
		ct, ok := viewerTypes[strings.ToLower(path.Ext(name))]
		if d.IsDir() || !ok || !d.Type().IsRegular() {
			return nil
		}
		b, err := read(rel)
		if err != nil {
			return err
		}
		if total += len(b); total > maxViewerBytes {
			return fmt.Errorf("the viewer files in %s are larger than %d MiB. Check MEMORIES_WEB_DIR", p.webDir, maxViewerBytes>>20)
		}
		p.assets[AssetPrefix+rel] = asset{body: b, contentType: ct, etag: etagOf(b)}
		return nil
	})
}

// Assets returns the handler of every path under /_/: the viewer code files from memory, the map art and the fonts
// from the disk, and a plain 404 for the rest.
func (p *Pages) Assets() http.Handler {
	mux := http.NewServeMux()
	mux.Handle("GET "+AssetPrefix+"map/", NewStatic(AssetPrefix+"map/", filepath.Join(p.webDir, "map"), MapTypes))
	mux.Handle("GET "+AssetPrefix+"fonts/", NewStatic(AssetPrefix+"fonts/", filepath.Join(p.webDir, "fonts"), FontTypes))
	for path, a := range p.assets {
		mux.Handle("GET "+path, serveBytes(a.contentType, a.etag, a.body))
	}
	mux.HandleFunc(AssetPrefix, http.NotFound)
	return mux
}

// Routes adds the catch-all route. It serves the character pages and gives the generic 404 page for every other
// path, so that an unknown path and a missing character look the same.
func (p *Pages) Routes(mux *http.ServeMux) {
	mux.Handle("/", p)
}

// serveBytes serves fixed bytes with an ETag, so that a browser asks again and gets a 304 until the file changes.
func serveBytes(contentType, etag string, body []byte) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		h := w.Header()
		h.Set("Content-Type", contentType)
		h.Set("Cache-Control", "no-cache")
		h.Set("ETag", etag)
		http.ServeContent(w, r, "", time.Time{}, bytes.NewReader(body))
	})
}

func etagOf(b []byte) string {
	sum := sha256.Sum256(b)
	return quotedHex(sum[:])
}

func quotedHex(sum []byte) string { return `"` + hex.EncodeToString(sum) + `"` }

// ServeHTTP serves /<f>/<r>/<realm>/<name>[/], its page and its data files. Any other path gives the 404 page.
func (p *Pages) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet && r.Method != http.MethodHead {
		p.notFound.ServeHTTP(w, r)
		return
	}
	trailing := strings.HasSuffix(r.URL.Path, "/")
	parts := strings.Split(strings.Trim(r.URL.Path, "/"), "/")
	if len(parts) < 4 {
		p.notFound.ServeHTTP(w, r)
		return
	}
	for _, seg := range parts[:4] {
		if !ids.Pattern.MatchString(seg) {
			p.notFound.ServeHTTP(w, r)
			return
		}
	}
	path := "/" + strings.Join(parts[:4], "/")
	switch {
	case len(parts) == 4 && !trailing:
		w.Header().Set("X-Robots-Tag", robotsNoIndex)
		http.Redirect(w, r, path+"/", http.StatusMovedPermanently)
	case len(parts) == 4:
		p.page(w, r, parts)
	case trailing || parts[4] != "data":
		p.notFound.ServeHTTP(w, r)
	case len(parts) == 6 && dataTypes[parts[5]] != "":
		p.data(w, r, parts, parts[5], dataTypes[parts[5]])
	case len(parts) == 7 && parts[5] == "screenshots" && shotName.MatchString(parts[6]):
		p.data(w, r, parts, "screenshots/"+parts[6], shotType(parts[6]))
	default:
		p.notFound.ServeHTTP(w, r)
	}
}

func shotType(file string) string {
	if strings.HasSuffix(file, ".png") {
		return "image/png"
	}
	return "image/jpeg"
}

// claim finds the character. It answers the request itself and returns false when there is no character or the
// lookup failed.
func (p *Pages) claim(w http.ResponseWriter, r *http.Request, parts []string) (store.Claim, bool) {
	c, err := p.claims.ClaimByPath(r.Context(), parts[0], parts[1], parts[2], parts[3])
	switch {
	case errors.Is(err, store.ErrNotFound):
		p.notFound.ServeHTTP(w, r)
		return c, false
	case err != nil:
		p.fail(w, r, "look up the character", err)
		return c, false
	}
	return c, true
}

func (p *Pages) fail(w http.ResponseWriter, r *http.Request, what string, err error) {
	p.log.Error("could not "+what, "path", r.URL.Path, "err", err.Error())
	http.Error(w, "Something went wrong on the server. Try again in a moment.", http.StatusInternalServerError)
}

func blobPath(id int64, rel string) string { return strconv.FormatInt(id, 10) + "/" + rel }

// page serves the viewer in single-character mode: index.html with data-entry on <body> and the character in <title>.
func (p *Pages) page(w http.ResponseWriter, r *http.Request, parts []string) {
	claim, ok := p.claim(w, r, parts)
	if !ok {
		return
	}
	title, err := p.title(r.Context(), claim)
	if errors.Is(err, fs.ErrNotExist) {
		p.notFound.ServeHTTP(w, r)
		return
	}
	if err != nil {
		p.fail(w, r, "read the character", err)
		return
	}
	var out bytes.Buffer
	out.Grow(len(p.index) + len(title) + len(entryAttr))
	out.Write(p.index[:p.titleAt[0]])
	out.WriteString(html.EscapeString(title))
	out.Write(p.index[p.titleAt[1]:p.attrAt])
	out.WriteString(entryAttr)
	out.Write(p.index[p.attrAt:])
	h := w.Header()
	h.Set("Content-Type", "text/html; charset=utf-8")
	h.Set("X-Robots-Tag", robotsNoIndex)
	h.Set("Cache-Control", "no-cache")
	h.Set("ETag", etagOf(out.Bytes()))
	http.ServeContent(w, r, "", time.Time{}, bytes.NewReader(out.Bytes()))
}

// title returns "<name> — <realm label> — Memories" from the stored character.json, once for each version of the
// file. It returns an error that matches fs.ErrNotExist when the claim has no character file. A file that does not
// parse gives the path names.
func (p *Pages) title(ctx context.Context, c store.Claim) (string, error) {
	f, err := p.blobs.Open(ctx, blobPath(c.ID, "character.json"))
	if err != nil {
		return "", err
	}
	defer f.Close()
	info, err := f.Stat()
	if err != nil {
		return "", err
	}
	return p.titles.get(etagKey{c.ID, "character.json", info.Size(), info.ModTime().UnixNano()}, func() (string, error) {
		var ch struct {
			Name       string `json:"name"`
			Realm      string `json:"realm"`
			RealmLabel string `json:"realmLabel"`
		}
		// The file is checked at upload, so a parse failure only means a damaged file: the page still opens.
		_ = json.NewDecoder(io.LimitReader(f, maxCharacterFile)).Decode(&ch)
		return cmp.Or(ch.Name, c.Name) + " — " + cmp.Or(ch.RealmLabel, ch.Realm, c.Realm) + " — Memories", nil
	})
}

// data streams one stored file of the claim.
func (p *Pages) data(w http.ResponseWriter, r *http.Request, parts []string, rel, contentType string) {
	claim, ok := p.claim(w, r, parts)
	if !ok {
		return
	}
	f, err := p.blobs.Open(r.Context(), blobPath(claim.ID, rel))
	if errors.Is(err, fs.ErrNotExist) {
		p.notFound.ServeHTTP(w, r)
		return
	}
	if err != nil {
		p.fail(w, r, "open a stored file", err)
		return
	}
	defer f.Close()
	info, err := f.Stat()
	if err != nil {
		p.fail(w, r, "read a stored file", err)
		return
	}
	etag, err := p.etags.of(etagKey{claim.ID, rel, info.Size(), info.ModTime().UnixNano()}, f)
	if err != nil {
		p.fail(w, r, "read a stored file", err)
		return
	}
	h := w.Header()
	h.Set("Content-Type", contentType)
	h.Set("X-Robots-Tag", robotsNoIndex)
	h.Set("Cache-Control", "no-cache")
	h.Set("ETag", etag)
	http.ServeContent(w, r, "", time.Time{}, f)
}

type etagKey struct {
	claim int64
	file  string
	size  int64
	mod   int64
}

// etagCache remembers a value derived from each file version, so that a file is read once. A save replaces a file by
// a rename, which gives it a new modification time, so the key changes and the old entry is never used again.
type etagCache struct {
	mu sync.Mutex
	m  map[etagKey]string
}

// of returns the cached ETag of the key, or hashes f and caches it. f is left at its start.
func (c *etagCache) of(k etagKey, f io.ReadSeeker) (string, error) {
	return c.get(k, func() (string, error) {
		h := sha256.New()
		if _, err := io.Copy(h, f); err != nil {
			return "", err
		}
		if _, err := f.Seek(0, io.SeekStart); err != nil {
			return "", err
		}
		return quotedHex(h.Sum(nil)), nil
	})
}

// get returns the cached value of the key, or computes and caches it.
func (c *etagCache) get(k etagKey, compute func() (string, error)) (string, error) {
	c.mu.Lock()
	v, ok := c.m[k]
	c.mu.Unlock()
	if ok {
		return v, nil
	}
	v, err := compute()
	if err != nil {
		return "", err
	}
	c.mu.Lock()
	// Deleted characters leave entries behind; starting over at the cap bounds the memory and costs one re-read per file.
	if len(c.m) >= maxCachedETags {
		clear(c.m)
	}
	c.m[k] = v
	c.mu.Unlock()
	return v, nil
}
