package ids

import (
	"errors"
	"strings"
	"testing"
)

func TestSlug(t *testing.T) {
	tests := []struct{ in, want string }{
		{"Ñandú", "nandu"},
		{"Los Errantes", "los-errantes"},
		{"Ner'zhul", "ner-zhul"},
		{"  --Aa--Bb--  ", "aa-bb"},
		{"ÑÑ", "nn"},
		{"日本語", ""},
		{"", ""},
		{"!!!", ""},
		{"ﬁsh", "fish"},
		{"Player-1234-0ABCDEF0", "player-1234-0abcdef0"},
	}
	for _, tc := range tests {
		if got := Slug(tc.in); got != tc.want {
			t.Errorf("Slug(%q) = %q, want %q", tc.in, got, tc.want)
		}
	}
}

func TestPath(t *testing.T) {
	char := func(m map[string]any) map[string]any {
		out := map[string]any{"flavor": "wow", "region": "EU", "realm": "Los Errantes", "name": "Ñandú", "guid": "Player-5678-0FEDCBA0"}
		for k, v := range m {
			out[k] = v
		}
		return out
	}
	tests := []struct {
		name    string
		in      map[string]any
		want    [4]string
		wantErr string
	}{
		{"plain", char(nil), [4]string{"wow", "eu", "los-errantes", "nandu"}, ""},
		{"flavor with underscore", char(map[string]any{"flavor": "classic_era"}), [4]string{"classic-era", "eu", "los-errantes", "nandu"}, ""},
		{"realm with dash and space", char(map[string]any{"realm": "Aa-Bb Cc"}), [4]string{"wow", "eu", "aa-bb-cc", "nandu"}, ""},
		{"name with no slug uses the guid", char(map[string]any{"name": "ÑÑ!"}), [4]string{"wow", "eu", "los-errantes", "nn"}, ""},
		{"name of non-latin letters uses the guid", char(map[string]any{"name": "日本"}), [4]string{"wow", "eu", "los-errantes", "player-5678-0fedcba0"}, ""},
		{"realm with no slug", char(map[string]any{"realm": "日本"}), [4]string{}, "realm"},
		{"name and guid with no slug", char(map[string]any{"name": "日本", "guid": "日本"}), [4]string{}, "name"},
		{"region with a digit and a symbol", char(map[string]any{"region": "E!"}), [4]string{}, "region"},
		{"flavor with no slug", char(map[string]any{"flavor": "_"}), [4]string{}, "flavor"},
		{"missing realm", map[string]any{"flavor": "wow", "region": "EU", "name": "A", "guid": "G"}, [4]string{}, `"realm"`},
		{"number as name", char(map[string]any{"name": 5}), [4]string{}, `"name"`},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			f, r, realm, name, err := Path(tc.in)
			if tc.wantErr != "" {
				var pe *PathError
				if !errors.As(err, &pe) || !strings.Contains(err.Error(), tc.wantErr) || !strings.Contains(tc.wantErr, pe.Field) {
					t.Fatalf("err = %v, want a PathError that contains %q", err, tc.wantErr)
				}
				return
			}
			if err != nil {
				t.Fatal(err)
			}
			if got := [4]string{f, r, realm, name}; got != tc.want {
				t.Errorf("Path = %v, want %v", got, tc.want)
			}
		})
	}
}
