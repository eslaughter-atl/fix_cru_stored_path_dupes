# fix_cru_stored_path_dupes
Identifies and removes any duplicate records in cru_stored_path, and then re-points any cru_revision records pointing to the dupes.   Then identifies any subsequent duplicates in cru_revision from this re-pointing, re-points THOSE dependencies, and then removes any duplicate records in cru_revision.   Lastly - re-calculates the hash data in cru_stored_path.cru_hash.
