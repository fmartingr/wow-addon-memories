package store

import (
	"context"
	"database/sql"
	"errors"
	"strconv"
)

const (
	settingOpen        = "open_registration"
	settingOpenMaxData = "open_max_data_bytes"
	settingOpenMinFree = "open_min_free_percent"
	defaultOpenMaxData = int64(64) << 20
	defaultOpenMinFree = int64(10)
)

// OpenSettings are the admin settings of open registration.
type OpenSettings struct {
	// Open lets a new key register without an invite.
	Open bool
	// MaxDataBytes is the most journey data that one open key may hold.
	MaxDataBytes int64
	// MinFreePercent closes open registration when the free space of the data disk is at this percent or less.
	MinFreePercent int64
}

// DefaultOpenSettings are the settings before the admin saves any.
func DefaultOpenSettings() OpenSettings {
	return OpenSettings{MaxDataBytes: defaultOpenMaxData, MinFreePercent: defaultOpenMinFree}
}

// SeedOpen sets the open registration switch to open when no value is stored yet. It changes nothing after the first
// start, so the admin page owns the switch from then on.
func (s *Store) SeedOpen(ctx context.Context, open bool) error {
	_, err := s.db.ExecContext(ctx, `INSERT INTO settings (name, value) VALUES (?, ?) ON CONFLICT(name) DO NOTHING`,
		settingOpen, boolText(open))
	return err
}

// OpenSettings returns the stored settings. A setting with no stored value takes its default.
func (s *Store) OpenSettings(ctx context.Context) (OpenSettings, error) {
	o := DefaultOpenSettings()
	rows, err := s.db.QueryContext(ctx, `SELECT name, value FROM settings WHERE name IN (?, ?, ?)`,
		settingOpen, settingOpenMaxData, settingOpenMinFree)
	if err != nil {
		return o, err
	}
	defer rows.Close()
	for rows.Next() {
		var name, value string
		if err := rows.Scan(&name, &value); err != nil {
			return o, err
		}
		n, err := strconv.ParseInt(value, 10, 64)
		if err != nil {
			return o, errors.New("store: setting " + name + " has the value " + strconv.Quote(value) + ", which is not a number")
		}
		switch name {
		case settingOpen:
			o.Open = n != 0
		case settingOpenMaxData:
			o.MaxDataBytes = n
		case settingOpenMinFree:
			o.MinFreePercent = n
		}
	}
	return o, rows.Err()
}

// SetOpenSettings stores all the settings in one transaction.
func (s *Store) SetOpenSettings(ctx context.Context, o OpenSettings) error {
	return s.inTx(ctx, func(tx *sql.Tx) error {
		for name, value := range map[string]string{
			settingOpen:        boolText(o.Open),
			settingOpenMaxData: strconv.FormatInt(o.MaxDataBytes, 10),
			settingOpenMinFree: strconv.FormatInt(o.MinFreePercent, 10),
		} {
			if _, err := tx.ExecContext(ctx,
				`INSERT INTO settings (name, value) VALUES (?, ?) ON CONFLICT(name) DO UPDATE SET value = excluded.value`,
				name, value); err != nil {
				return err
			}
		}
		return nil
	})
}

// CloseOpen turns open registration off. It returns true when the switch was on, so that only one caller reports the
// change.
func (s *Store) CloseOpen(ctx context.Context) (bool, error) {
	res, err := s.db.ExecContext(ctx, `UPDATE settings SET value = '0' WHERE name = ? AND value <> '0'`, settingOpen)
	if err != nil {
		return false, err
	}
	n, err := res.RowsAffected()
	return n > 0, err
}

func boolText(b bool) string {
	if b {
		return "1"
	}
	return "0"
}
