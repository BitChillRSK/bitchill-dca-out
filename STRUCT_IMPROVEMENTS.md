# DcaOutSchedule Struct Improvements

## Issues Identified & Fixed

### 1. ✅ **Removed Redundant `docBalance` Field**

**Problem:** `DcaOutSchedule.docBalance` was unnecessary because:
- DOC balances are tracked in `s_userDocBalances[user]` mapping
- No equivalent field exists in `DcaManager` (rBTC balances tracked in handlers)
- `withdrawDoc()` doesn't need to update schedule fields

**Solution:** Removed `docBalance` from struct, kept `s_userDocBalances` mapping.

---

### 2. ✅ **Removed Unnecessary `active` Field**

**Problem:** `DcaOutSchedule.active` field was not needed because:
- `DcaManager` doesn't have an `active` field
- Schedules are **physically removed** from array when deleted (not marked inactive)
- Cleaner design - no "zombie" schedules

**Solution:** 
- Removed `active` field from struct
- Updated `deleteSchedule()` to use `DcaManager` pattern:
  ```solidity
  // Remove by swapping with last element and popping
  uint256 lastIndex = schedules.length - 1;
  if (scheduleIndex != lastIndex) {
      schedules[scheduleIndex] = schedules[lastIndex];
  }
  schedules.pop();
  ```

---

### 3. ✅ **Added Missing `updateSchedule` Function**

**Problem:** No way to update existing schedules (unlike `DcaManager.updateDcaSchedule()`)

**Solution:** Added `updateSchedule()` function matching `DcaManager` pattern:
```solidity
function updateSchedule(
    uint256 scheduleIndex,
    bytes32 scheduleId,
    uint256 depositAmount,  // 0 to skip
    uint256 rbtcAmount,     // 0 to skip  
    uint256 period          // 0 to skip
) external payable;
```

**Features:**
- ✅ Schedule ID validation (prevents race conditions)
- ✅ Optional updates (0 = skip field)
- ✅ Deposit rBTC during update
- ✅ Validates all inputs
- ✅ Emits `ScheduleUpdated` event

---

### 4. ✅ **Added Comprehensive Getter Functions**

**Problem:** Missing getter functions that exist in `DcaManager`

**Solution:** Added all getter functions following `DcaManager` pattern:

```solidity
// Array getters
function getMySchedules() external view returns (DcaOutSchedule[] memory);
function getSchedules(address user) external view returns (DcaOutSchedule[] memory);

// Individual field getters (with "My" variants)
function getMyScheduleRbtcBalance(uint256 scheduleIndex) external view returns (uint256);
function getScheduleRbtcBalance(address user, uint256 scheduleIndex) external view returns (uint256);

function getMyScheduleSaleAmount(uint256 scheduleIndex) external view returns (uint256);
function getScheduleRbtcAmount(address user, uint256 scheduleIndex) external view returns (uint256);

function getMySchedulePeriod(uint256 scheduleIndex) external view returns (uint256);
function getSchedulePeriod(address user, uint256 scheduleIndex) external view returns (uint256);

function getMyScheduleId(uint256 scheduleIndex) external view returns (bytes32);
function getScheduleId(address user, uint256 scheduleIndex) external view returns (bytes32);
```

**Benefits:**
- ✅ Consistent with `DcaManager` API
- ✅ Frontend can query specific fields without fetching entire schedule
- ✅ Gas efficient for individual field queries
- ✅ "My" variants for user convenience

---

## Final Struct Design

```solidity
struct DcaOutSchedule {
    uint256 rbtcAmount;        // Amount of rBTC to sell per period
    uint256 period;            // Time between sells (in seconds)
    uint256 lastSaleTimestamp; // Timestamp of last execution
    uint256 rbtcBalance;       // Current rBTC balance deposited
    bytes32 scheduleId;        // Unique identifier
}
```

**Removed fields:**
- ❌ `docBalance` (tracked in `s_userDocBalances[user]`)
- ❌ `active` (schedules physically removed when deleted)

---

## Test Results

```
Ran 22 tests for test/DcaOutManagerTest.t.sol:DcaOutManagerTest
[PASS] All 22 tests ✅
Suite result: ok. 22 passed; 0 failed; 0 skipped
```

---

## Key Improvements Summary

1. **Cleaner Data Model** - Removed redundant fields
2. **Better UX** - Added `updateSchedule()` function  
3. **Complete API** - Added all getter functions from `DcaManager`
4. **Consistent Patterns** - Matches `DcaManager` deletion and getter patterns
5. **Gas Efficient** - Individual field getters, no unnecessary storage

The `DcaOutSchedule` struct is now optimized and fully aligned with your `DcaManager` patterns! 🎯
