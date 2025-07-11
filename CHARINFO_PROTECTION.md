# Character Information Protection

This file documents the charinfo protection system implemented in fox-multicharacter to prevent stale data overwrites.

## Problem

When players change their names using fox-namechange, the SQL table updates correctly, but on disconnect/reconnect, the name reverts to the old value. This happens because cached charinfo data overwrites the fresh SQL data.

## Solution

The protection system includes:

### 1. Legitimate Update Tracking
- `MarkLegitimateCharinfoUpdate(citizenid, reason)` - Marks updates as legitimate
- `IsLegitimateCharinfoUpdate(citizenid)` - Checks if update is legitimate
- 5-minute window for legitimate updates

### 2. Fresh Data Loading
- Modified `setupCharacters` callback to always fetch fresh SQL data
- Added logging for all charinfo operations
- Ensures character selection always shows latest names

### 3. External Integration
- `markCharinfoUpdate(citizenid, reason)` export for other resources
- `refreshCharinfo(citizenid, reason)` export to trigger refresh
- Event handlers for external charinfo updates

### 4. Logging & Monitoring
- Comprehensive logging of all charinfo operations
- Warnings for potential stale overwrites
- Operation tracking with timestamps

## Usage for Other Resources

If you're developing a resource that modifies charinfo (like fox-namechange), use:

```lua
-- Before updating charinfo in SQL
exports['qb-multicharacter']:markCharinfoUpdate(citizenid, "Name Change")

-- After updating charinfo in SQL
exports['qb-multicharacter']:refreshCharinfo(citizenid, "Name Change")
```

## Events

### `qb-multicharacter:server:refreshCharinfo`
Marks charinfo as updated externally and refreshes player data if online.

### `qb-multicharacter:server:warnStaleCharinfo`
Warns about potential stale charinfo overwrites.

## Log Monitoring

Watch for these log entries:
- `CHARINFO STALE_WARNING` - Indicates potential data corruption
- `CHARINFO FETCH_SQL` - Shows fresh data being loaded
- `CHARINFO CREATE_*` - Character creation operations
- `CHARINFO LOAD_*` - Character loading operations

## Important Notes

1. **Never modify charinfo without marking it as legitimate first**
2. **Always fetch fresh SQL data when loading characters**
3. **Monitor logs for stale warning entries**
4. **Clean up protection data on resource stop**