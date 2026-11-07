// Package export turns the Memories saved files of a WoW flavor folder into the dist-characters folder layout.
package export

import (
	"bytes"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"time"

	"github.com/fmartingr/wow-addon-memories/internal/journal"
	"github.com/fmartingr/wow-addon-memories/internal/savedvars"
)

// CoreAddon is the addon whose saved file holds the character, its sessions and its trail.
const CoreAddon = "Memories"

// ErrUsage marks an error in the options, as opposed to an error during the run.
var ErrUsage = errors.New("usage")

var subAddonFile = regexp.MustCompile(`^Memories_([A-Za-z0-9]+)\.lua$`)

// Options configure a run.
type Options struct {
	WowDir  string
	Dist    string
	Backup  string
	Default string
	Now     time.Time
	Out     io.Writer
}

type character struct {
	id, guid, name, realm string
	char                  map[string]any
	addons                map[string]map[string]any
	addonNames            []string
	records               []journal.Record
	trail                 []journal.Chunk
	sessions              []map[string]any
	last                  int64
}

type runner struct {
	Options
	wow, flavor, region, backupDir string
	earlier                        map[string]any
	files, damaged, badLines       int
	badChunks, joined              int
	failed, skipped                int
}

// Run converts every character of the flavor folder o.WowDir. It reads the saved files and the screenshots and never
// writes below WTF or Screenshots.
func Run(o Options) error {
	r, err := newRunner(o)
	if err != nil {
		return err
	}
	// Writing over an index that cannot be read would drop the entries and the default that it keeps.
	if r.earlier, err = readJSON(filepath.Join(r.Dist, "index.json")); err != nil {
		return fmt.Errorf("%w; fix or remove it", err)
	}
	chars, err := r.scan()
	if err != nil {
		return err
	}
	if len(chars) == 0 {
		return fmt.Errorf("no character with Memories data under %s; log out of the game or /reload first", r.wow)
	}
	r.assignIDs(chars)
	ids := map[string]bool{}
	for _, c := range chars {
		ids[c.id] = true
	}
	if r.Default != "" && !ids[r.Default] {
		return fmt.Errorf("%w: --default %q is not a character id", ErrUsage, r.Default)
	}

	var ready []*character
	for _, c := range chars {
		if err := r.mergeEarlier(c); err != nil {
			r.warn("%s: %v; its folder is left as it was", c.id, err)
			r.failed++
			continue
		}
		ready = append(ready, c)
	}
	copied, unmatched, err := r.screenshots(ready)
	if err != nil {
		return err
	}
	var index []indexEntry
	for _, c := range ready {
		e, err := r.write(c)
		if err != nil {
			return err
		}
		index = append(index, e)
		r.info("%s: %d records, %d trail points, %d sessions, %d screenshots, addons %s",
			c.id, e.Steps, e.TrailPoints, e.Sessions, e.Screenshots, strings.Join(e.Addons, ", "))
	}
	if err := r.writeIndex(index); err != nil {
		return err
	}
	r.info("read %d files (%d damaged), skipped %d lines and %d trail chunks, joined %d notes",
		r.files, r.damaged, r.badLines, r.badChunks, r.joined)
	r.info("copied %d screenshots, %d not found; backup in %s", copied, unmatched, r.backupDir)
	r.info("wrote %d characters to %s", len(index), r.Dist)
	if r.failed > 0 || r.skipped > 0 {
		return fmt.Errorf("%d characters and %d accounts failed", r.failed, r.skipped)
	}
	return nil
}

func newRunner(o Options) (*runner, error) {
	if o.Out == nil {
		o.Out = io.Discard
	}
	if o.Now.IsZero() {
		o.Now = time.Now()
	}
	r := &runner{Options: o}
	var err error
	if r.wow, err = filepath.Abs(o.WowDir); err != nil {
		return nil, err
	}
	if r.Dist, err = filepath.Abs(o.Dist); err != nil {
		return nil, err
	}
	if r.Backup, err = filepath.Abs(o.Backup); err != nil {
		return nil, err
	}
	for _, out := range []string{r.Dist, r.Backup} {
		for _, src := range []string{"WTF", "Screenshots"} {
			// An output folder that holds the source folder would let a character id such as "wtf" name it.
			if s := filepath.Join(r.wow, src); inside(out, s) || inside(s, out) {
				return nil, fmt.Errorf("%w: %s overlaps %s, which the converter never writes", ErrUsage, out, src)
			}
		}
	}
	if info, err := os.Stat(filepath.Join(r.wow, "WTF", "Account")); err != nil || !info.IsDir() {
		return nil, fmt.Errorf("%s has no WTF/Account folder; pass a flavor folder such as .../World of Warcraft/_forever_", r.wow)
	}
	r.flavor = filepath.Base(r.wow)
	r.region = "xx"
	if cfg, err := os.ReadFile(filepath.Join(r.wow, "WTF", "Config.wtf")); err == nil {
		r.region = Region(string(cfg))
	}
	r.backupDir = filepath.Join(r.Backup, r.Now.UTC().Format("20060102T150405Z"))
	return r, nil
}

func (r *runner) info(format string, args ...any) {
	_, _ = fmt.Fprintf(r.Out, format+"\n", args...)
}

func (r *runner) warn(format string, args ...any) {
	_, _ = fmt.Fprintf(r.Out, "warning: "+format+"\n", args...)
}

func dirs(path string) ([]string, error) {
	entries, err := os.ReadDir(path)
	if err != nil {
		return nil, err
	}
	var out []string
	for _, e := range entries {
		if e.IsDir() && e.Name() != "SavedVariables" {
			out = append(out, e.Name())
		}
	}
	return out, nil
}

func isFile(path string) bool {
	info, err := os.Lstat(path)
	return err == nil && info.Mode().IsRegular()
}

// read backs up a saved file, then parses its copy in memory. A damaged file is reported and gives nil.
func (r *runner) read(path, global string) map[string]any {
	r.files++
	src, err := os.ReadFile(path)
	if err != nil {
		r.warn("%s: %v", path, err)
		r.damaged++
		return nil
	}
	rel, err := filepath.Rel(filepath.Join(r.wow, "WTF", "Account"), path)
	if err != nil {
		return nil
	}
	if err := writeAtomic(filepath.Join(r.backupDir, "savedvariables", r.flavor, rel), src); err != nil {
		r.warn("backup of %s: %v", path, err)
	}
	vars, err := savedvars.Parse(bytes.NewReader(src))
	if err != nil {
		r.warn("%s: %v; file skipped", path, err)
		r.damaged++
		return nil
	}
	data, ok := vars[global].(map[string]any)
	if !ok {
		r.warn("%s has no %s table; file skipped", path, global)
		return nil
	}
	return data
}

func (r *runner) scan() ([]*character, error) {
	accountsDir := filepath.Join(r.wow, "WTF", "Account")
	accounts, err := dirs(accountsDir)
	if err != nil {
		return nil, err
	}
	byGUID := map[string]*character{}
accounts:
	for _, acc := range accounts {
		// Without the kinds every field lands in "extra", so no record would match its copy of an earlier run and the
		// journal would hold each record twice. An account without the file and without character data is not an error.
		var kinds journal.Kinds
		accFile := filepath.Join(accountsDir, acc, "SavedVariables", "Memories.lua")
		if isFile(accFile) {
			db := r.read(accFile, "MemoriesDB")
			if db == nil {
				r.warn("account %s: its characters are skipped until its Memories.lua can be read", acc)
				r.skipped++
				continue
			}
			if kinds = journal.ParseKinds(db["kinds"]); len(kinds) == 0 {
				r.warn("account %s: its Memories.lua has no kinds; its characters are skipped", acc)
				r.skipped++
				continue
			}
		}
		realms, err := dirs(filepath.Join(accountsDir, acc))
		if err != nil {
			return nil, err
		}
		for _, realm := range realms {
			names, err := dirs(filepath.Join(accountsDir, acc, realm))
			if err != nil {
				return nil, err
			}
			for _, name := range names {
				sv := filepath.Join(accountsDir, acc, realm, name, "SavedVariables")
				if kinds == nil {
					if isFile(filepath.Join(sv, "Memories.lua")) {
						r.warn("account %s has character data but no Memories.lua; its characters are skipped", acc)
						r.skipped++
						continue accounts
					}
					continue
				}
				cname, crealm := charFolder(realm, name)
				c := r.load(sv, crealm, cname, kinds)
				if c == nil {
					continue
				}
				if old, ok := byGUID[c.guid]; ok {
					r.warn("%s-%s has the GUID of %s-%s; the one played last is kept", c.name, c.realm, old.name, old.realm)
					if c.last < old.last {
						continue
					}
				}
				byGUID[c.guid] = c
			}
		}
	}
	chars := make([]*character, 0, len(byGUID))
	for _, c := range byGUID {
		chars = append(chars, c)
	}
	return chars, nil
}

// charFolder gives the name and realm of a character folder. The Forever client names it "<Name>-<Realm>" inside a
// realm id folder such as "93"; other clients name it "<Name>" inside a "<Realm>" folder. A name never holds a "-",
// so the realm is all the text after the first one.
func charFolder(parent, folder string) (name, realm string) {
	if n, r, ok := strings.Cut(folder, "-"); ok && n != "" && r != "" {
		return n, r
	}
	return folder, parent
}

func (r *runner) load(sv, realm, folder string, kinds journal.Kinds) *character {
	corePath := filepath.Join(sv, "Memories.lua")
	if !isFile(corePath) {
		return nil
	}
	db := r.read(corePath, "MemoriesCharDB")
	if db == nil {
		return nil
	}
	char, _ := db["char"].(map[string]any)
	guid, _ := char["guid"].(string)
	if guid == "" {
		r.info("%s-%s: no character GUID in Memories.lua, skipped", folder, realm)
		return nil
	}
	c := &character{guid: guid, realm: realm, char: char, addons: map[string]map[string]any{CoreAddon: db}}
	if c.name, _ = char["name"].(string); c.name == "" {
		c.name = folder
	}
	entries, _ := os.ReadDir(sv)
	var subs []string
	for _, e := range entries {
		m := subAddonFile.FindStringSubmatch(e.Name())
		if m == nil || !isFile(filepath.Join(sv, e.Name())) {
			continue
		}
		if data := r.read(filepath.Join(sv, e.Name()), "Memories"+m[1]+"CharDB"); data != nil {
			addon := "Memories_" + m[1]
			// A sub-addon turned off for this character keeps a file that the game never rewrites, such as one copied
			// from another character's folder; the addon itself moves such data to the orphans when it loads.
			subChar, _ := data["char"].(map[string]any)
			if g, _ := subChar["guid"].(string); g != "" && g != guid {
				r.warn("%s belongs to the character with GUID %s; file skipped", filepath.Join(sv, e.Name()), g)
				continue
			}
			c.addons[addon] = data
			subs = append(subs, addon)
		}
	}
	sort.Strings(subs)
	c.addonNames = append([]string{CoreAddon}, subs...)

	for _, addon := range c.addonNames {
		for _, line := range journal.Lines(c.addons[addon]["log"]) {
			rec, err := journal.Decode(line, kinds)
			if err != nil {
				r.badLines++
				continue
			}
			rec["addon"] = addon
			c.records = append(c.records, rec)
		}
	}
	var joined int
	c.records, joined = JoinNotes(c.records)
	r.joined += joined
	var bad int
	c.trail, bad = journal.Trail(db["trail"])
	r.badChunks += bad
	c.sessions = MergeSessions(journal.List(db["sessions"]))
	for _, s := range c.sessions {
		c.last = max(c.last, lastOf(s))
	}
	return c
}

func entryOf(v any) (id, guid string, e map[string]any) {
	e, _ = v.(map[string]any)
	id, _ = e["id"].(string)
	guid, _ = e["guid"].(string)
	return id, guid, e
}

// assignIDs keeps the id of an earlier run while the character's name and realm still give it, so a folder never
// changes owner. A new character gets an id in the order the characters were played, so the one played first keeps
// the plain id.
func (r *runner) assignIDs(chars []*character) {
	sort.Slice(chars, func(i, j int) bool {
		if chars[i].last != chars[j].last {
			return chars[i].last < chars[j].last
		}
		return chars[i].guid < chars[j].guid
	})
	taken := map[string]string{}
	earlier := map[string]string{}
	list, _ := r.earlier["characters"].([]any)
	for _, v := range list {
		if id, guid, _ := entryOf(v); IDPattern.MatchString(id) && guid != "" {
			taken[id], earlier[guid] = guid, id
		}
	}
	// A folder that left the index, such as the one of a renamed character, still belongs to its GUID.
	entries, _ := os.ReadDir(r.Dist)
	for _, e := range entries {
		if _, ok := taken[e.Name()]; ok || !e.IsDir() || !IDPattern.MatchString(e.Name()) {
			continue
		}
		old, _ := readJSON(filepath.Join(r.Dist, e.Name(), "character.json"))
		if guid, _ := old["guid"].(string); guid != "" {
			taken[e.Name()] = guid
		}
	}
	for _, c := range chars {
		base := BaseID(r.region, c.realm, c.name, c.guid)
		if id, ok := earlier[c.guid]; ok && isCandidate(id, base, r.flavor, c.guid) {
			c.id = id
			continue
		}
		c.id = AssignID(taken, base, r.flavor, c.guid)
	}
	sort.Slice(chars, func(i, j int) bool { return chars[i].id < chars[j].id })
}

func (r *runner) mergeEarlier(c *character) error {
	folder := filepath.Join(r.Dist, c.id)
	oldRecords, err := readJSONL[journal.Record](filepath.Join(folder, "journey.jsonl"))
	if err != nil {
		return err
	}
	oldTrail, err := readJSONL[journal.Chunk](filepath.Join(folder, "trail.jsonl"))
	if err != nil {
		return err
	}
	oldChar, err := readJSON(filepath.Join(folder, "character.json"))
	if err != nil {
		return err
	}
	if guid, ok := oldChar["guid"].(string); ok && guid != c.guid {
		return fmt.Errorf("the folder holds the character with GUID %s", guid)
	}
	c.records = MergeRecords(oldRecords, c.records)
	c.trail = MergeTrail(oldTrail, c.trail)
	oldSessions, _ := oldChar["sessions"].([]any)
	fresh := make([]any, len(c.sessions))
	for i, s := range c.sessions {
		fresh[i] = s
	}
	c.sessions = MergeSessions(oldSessions, fresh)
	for _, rec := range c.records {
		if i, _, _ := SessionAt(c.sessions, rec.T()); i > 0 {
			rec["session"] = i
		} else {
			rec["session"] = nil
		}
	}
	return nil
}

func listScreenshots(dir string) ([]string, error) {
	entries, err := os.ReadDir(dir)
	if errors.Is(err, fs.ErrNotExist) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	var names []string
	for _, e := range entries {
		if e.Type().IsRegular() && FileNamePattern.MatchString(e.Name()) {
			names = append(names, e.Name())
		}
	}
	return names, nil
}

type shotRef struct {
	c   *character
	rec journal.Record
}

func (r *runner) screenshots(chars []*character) (copied, unmatched int, err error) {
	src := filepath.Join(r.wow, "Screenshots")
	files, err := listScreenshots(src)
	if err != nil {
		return 0, 0, err
	}
	claimed := map[string]bool{}
	var shots []Shot
	var refs []shotRef
	for _, c := range chars {
		for _, rec := range c.records {
			if s := rec.String("screenshot"); s != "" {
				claimed[strings.TrimPrefix(s, "screenshots/")] = true
				continue
			}
			k, file := rec.String("k"), rec.String("file")
			if (k != "ss" && k != "sn") || file == "" || rec.String("result") == "failed" {
				continue
			}
			_, tz, hasTZ := SessionAt(c.sessions, rec.T())
			shots = append(shots, Shot{File: file, T: rec.T(), TZ: tz, HasTZ: hasTZ})
			refs = append(refs, shotRef{c, rec})
		}
	}
	for i, j := range MatchShots(shots, files, claimed) {
		if j < 0 {
			unmatched++
			continue
		}
		name := files[j]
		from := filepath.Join(src, name)
		dst := filepath.Join(r.Dist, refs[i].c.id, "screenshots", name)
		did, err := copyFile(from, dst)
		if err != nil {
			r.warn("%s: %v; screenshot skipped", from, err)
			continue
		}
		if did {
			copied++
		}
		if _, err := copyFile(dst, filepath.Join(r.backupDir, "screenshots", name)); err != nil {
			r.warn("backup of %s: %v", from, err)
		}
		refs[i].rec["screenshot"] = "screenshots/" + name
	}
	return copied, unmatched, nil
}

type addonInfo struct {
	Counts    any `json:"counts"`
	Snap      any `json:"snap"`
	Schema    any `json:"schema"`
	WrittenBy any `json:"writtenBy"`
}

type indexEntry struct {
	ID          string   `json:"id"`
	GUID        string   `json:"guid"`
	Name        string   `json:"name"`
	Region      string   `json:"region"`
	Realm       string   `json:"realm"`
	Flavor      string   `json:"flavor"`
	Class       any      `json:"class"`
	Race        any      `json:"race"`
	Sex         any      `json:"sex"`
	Faction     any      `json:"faction"`
	Level       any      `json:"level"`
	Path        string   `json:"path"`
	Journey     string   `json:"journey"`
	Trail       string   `json:"trail"`
	Character   string   `json:"character"`
	Steps       int      `json:"steps"`
	Sessions    int      `json:"sessions"`
	TrailPoints int      `json:"trailPoints"`
	Screenshots int      `json:"screenshots"`
	Addons      []string `json:"addons"`
	Start       *int64   `json:"start"`
	End         *int64   `json:"end"`
	last        int64
}

// byLevel keeps the snapshots keyed by level. The parser turns a gap-free table of levels 1..n into a list.
func byLevel(v any) any {
	list, ok := v.([]any)
	if !ok {
		return v
	}
	out := make(map[string]any, len(list))
	for i, s := range list {
		out[strconv.Itoa(i+1)] = s
	}
	return out
}

func (r *runner) write(c *character) (indexEntry, error) {
	folder := filepath.Join(r.Dist, c.id)
	if err := writeJSONL(filepath.Join(folder, "journey.jsonl"), c.records); err != nil {
		return indexEntry{}, err
	}
	if err := writeJSONL(filepath.Join(folder, "trail.jsonl"), c.trail); err != nil {
		return indexEntry{}, err
	}
	flavor := strings.Trim(r.flavor, "_")
	region := strings.ToUpper(r.region)
	doc := make(map[string]any, len(c.char)+8)
	for k, v := range c.char {
		doc[k] = v
	}
	addons := map[string]addonInfo{}
	for _, a := range c.addonNames {
		d := c.addons[a]
		addons[a] = addonInfo{Counts: d["counts"], Snap: byLevel(d["snap"]), Schema: d["schema"], WrittenBy: d["writtenBy"]}
	}
	doc["region"], doc["realm"], doc["realmLabel"], doc["flavor"] = region, c.realm, c.char["realm"], flavor
	doc["sessions"], doc["flags"], doc["addons"] = c.sessions, c.addons[CoreAddon]["flags"], addons
	b, err := marshalIndent(doc)
	if err != nil {
		return indexEntry{}, err
	}
	if err := writeAtomic(filepath.Join(folder, "character.json"), b); err != nil {
		return indexEntry{}, err
	}

	e := indexEntry{
		ID: c.id, GUID: c.guid, Name: c.name, Region: region, Realm: c.realm, Flavor: flavor,
		Class: c.char["class"], Race: c.char["race"], Sex: c.char["sex"], Faction: c.char["faction"], Level: c.char["level"],
		Path: c.id, Journey: c.id + "/journey.jsonl", Trail: c.id + "/trail.jsonl", Character: c.id + "/character.json",
		Steps: len(c.records), Sessions: len(c.sessions), Addons: c.addonNames, last: c.last,
	}
	for _, ch := range c.trail {
		e.TrailPoints += ch.N
	}
	for _, rec := range c.records {
		if rec.String("screenshot") != "" {
			e.Screenshots++
		}
	}
	if n := len(c.records); n > 0 {
		start, end := c.records[0].T(), c.records[n-1].T()
		e.Start, e.End = &start, &end
		e.last = max(e.last, end)
	}
	return e, nil
}

// writeIndex lists the characters of this run and keeps every earlier entry whose character this run did not write, so
// a character whose run failed, or whose saved files are gone, stays on the website with its folder.
func (r *runner) writeIndex(index []indexEntry) error {
	old := r.earlier
	type row struct {
		id    string
		entry any
	}
	rows := make([]row, 0, len(index))
	ids, guids := map[string]bool{}, map[string]bool{}
	for _, e := range index {
		rows = append(rows, row{e.ID, e})
		ids[e.ID], guids[e.GUID] = true, true
	}
	list, _ := old["characters"].([]any)
	for _, v := range list {
		if id, guid, e := entryOf(v); IDPattern.MatchString(id) && !ids[id] && !guids[guid] {
			rows = append(rows, row{id, e})
			ids[id] = true
		}
	}
	sort.SliceStable(rows, func(i, j int) bool { return rows[i].id < rows[j].id })
	characters := make([]any, len(rows))
	for i, rw := range rows {
		characters[i] = rw.entry
	}

	def := r.Default
	if def != "" && !ids[def] {
		r.warn("--default %q has no entry in index.json; the earlier or latest character is used", def)
		def = ""
	}
	if kept, _ := old["default_character"].(string); def == "" && ids[kept] {
		def = kept
	}
	if def == "" {
		var best int64 = -1
		for _, e := range index {
			if e.last > best {
				best, def = e.last, e.ID
			}
		}
	}
	b, err := marshalIndent(map[string]any{"default_character": def, "characters": characters})
	if err != nil {
		return err
	}
	return writeAtomic(filepath.Join(r.Dist, "index.json"), b)
}
