-- dropping cru_source_rev_path_hash, comment this out if running on a DB prior to the upgrade attempt.
ALTER TABLE dbo.cru_revision
  DROP COLUMN cru_source_rev_path_hash;

-- create conversion tables
CREATE TABLE dbo.tmp_cru_stored_path_conversion
  (
     new_id INT,
     old_id INT
  );

INSERT INTO tmp_cru_stored_path_conversion
            (old_id,
             new_id)
SELECT sp.cru_path_id old_id,
       tmp.min_id     new_id
FROM   (SELECT Min(cru_path_id) min_id,
               cru_path
        FROM   dbo.cru_stored_path
        GROUP  BY cru_path) tmp
       JOIN dbo.cru_stored_path sp
         ON tmp.cru_path = sp.cru_path;

CREATE TABLE dbo.tmp_cru_revision_conversion
  (
     new_id INT,
     old_id INT
  );

INSERT INTO tmp_cru_revision_conversion
            (new_id,
             old_id)
(SELECT tmp.min_id,
        rev.cru_revision_id
 FROM   dbo.cru_revision rev
        JOIN dbo.tmp_cru_stored_path_conversion spconv
          ON rev.cru_path = spconv.old_id
        JOIN (SELECT Min(rev.cru_revision_id) min_id,
                     rev.cru_source_name,
                     spconv.new_id,
                     rev.cru_revision
              FROM   dbo.cru_revision rev
                     JOIN dbo.tmp_cru_stored_path_conversion spconv
                       ON rev.cru_path = spconv.old_id
              GROUP  BY rev.cru_source_name,
                        spconv.new_id,
                        rev.cru_revision) tmp
          ON tmp.cru_source_name = rev.cru_source_name
             AND tmp.new_id = spconv.new_id
             AND tmp.cru_revision = rev.cru_revision);

-- update cru_revision dependencies
UPDATE dbo.cru_feindex_msg
SET    cru_feindex_msg.cru_fr_id = conv.new_id
FROM   dbo.cru_feindex_msg fm
       JOIN tmp_cru_revision_conversion conv
         ON fm.cru_fr_id = conv.old_id;

UPDATE dbo.cru_patch_revision
SET    cru_revision_id = conv.new_id
FROM   dbo.cru_patch_revision pr
       JOIN tmp_cru_revision_conversion conv
         ON pr.cru_revision_id = conv.old_id;

DELETE fd
FROM   dbo.cru_fr_detail fd
       JOIN dbo.tmp_cru_revision_conversion conv
         ON fd.cru_revision_id = conv.old_id
            AND conv.new_id <> conv.old_id;

UPDATE dbo.cru_frx_revision
SET    cru_revision = conv.new_id
FROM   dbo.cru_frx_revision fr
       JOIN tmp_cru_revision_conversion conv
         ON fr.cru_revision = conv.old_id;

-- remove duplicates from cru_revisions
ALTER TABLE dbo.cru_revision
  DROP CONSTRAINT uk_crurevision_spr;

UPDATE dbo.cru_revision
SET    cru_path = conv.new_id
FROM   dbo.cru_revision rev
       JOIN dbo.tmp_cru_stored_path_conversion conv
         ON rev.cru_path = conv.old_id;

DELETE rev
FROM   dbo.cru_revision rev
       JOIN dbo.tmp_cru_revision_conversion conv
         ON rev.cru_revision_id = conv.old_id
WHERE  conv.new_id <> conv.old_id;

ALTER TABLE dbo.cru_revision
  ADD CONSTRAINT uk_crurevision_spr UNIQUE (cru_source_name, cru_path,
  cru_revision);

-- remove duplicates from cru_stored_path
DELETE path
FROM   dbo.cru_stored_path path
       JOIN dbo.tmp_cru_stored_path_conversion conv
         ON path.cru_path_id = conv.old_id
WHERE  conv.new_id <> conv.old_id;

-- recalculate hashes as customer has manually changed paths
UPDATE dbo.cru_stored_path
SET    cru_hash = CONVERT(NVARCHAR(128), Hashbytes('SHA2_256', cast(cru_path as varchar(1000))), 2);

-- drop conversion tables
DROP TABLE dbo.tmp_cru_stored_path_conversion;

DROP TABLE dbo.tmp_cru_revision_conversion; 
