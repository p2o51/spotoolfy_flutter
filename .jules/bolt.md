## 2024-05-24 - Parallelizing Independent SharedPreferences Writes
**Learning:** Writing to SharedPreferences using `await` in sequence adds up disk I/O wait times unnecessarily. Flutter/Dart's `Future.wait` allows these independent writes to execute in parallel, taking significantly less total wall clock time.
**Action:** Use `Future.wait` when writing multiple independent values to SharedPreferences concurrently instead of sequential `await`s.
