-- dropping cru_source_rev_path_hash, comment this out if running on a DB prior to the upgrade attempt.

ALTER TABLE cru_revision DROP COLUMN cru_source_rev_path_hash;

-- create conversion tables
 
CREATE TABLE tmp_cru_stored_path_conversion (new_id INT, old_id INT);

INSERT 
  INTO tmp_cru_stored_path_conversion (old_id, new_id)
SELECT sp.cru_path_id old_id,
       tmp.min_id new_id
  FROM (SELECT Min(cru_path_id) min_id, cru_path FROM cru_stored_path GROUP BY cru_path) tmp 
  JOIN cru_stored_path sp
    ON tmp.cru_path = sp.cru_path;

CREATE TABLE tmp_cru_revision_conversion (new_id INT, old_id INT);

 INSERT 
   INTO tmp_cru_revision_conversion (new_id, old_id)
(SELECT tmp.min_id, rev.cru_revision_id
   FROM cru_revision rev 
   JOIN tmp_cru_stored_path_conversion spconv 
     ON rev.cru_path = spconv.old_id 
   JOIN (SELECT Min(rev.cru_revision_id) min_id, rev.cru_source_name, spconv.new_id, rev.cru_revision FROM cru_revision rev JOIN tmp_cru_stored_path_conversion spconv ON rev.cru_path = spconv.old_id GROUP BY rev.cru_source_name, spconv.new_id, rev.cru_revision) tmp 
     ON tmp.cru_source_name = rev.cru_source_name
    AND tmp.new_id = spconv.new_id
    AND tmp.cru_revision = rev.cru_revision);
   
-- update cru_revision dependencies

UPDATE cru_feindex_msg fm
  JOIN tmp_cru_revision_conversion conv 
    ON fm.cru_fr_id = conv.old_id
   SET cru_fr_id = conv.new_id;

UPDATE cru_patch_revision pr
  JOIN tmp_cru_revision_conversion conv
    ON pr.cru_revision_id = conv.old_id
   SET cru_revision_id = conv.new_id;

  DELETE
    FROM cru_fr_detail
   WHERE cru_revision_id IN 
 (SELECT fd.cru_revision_id
    FROM (SELECT cru_revision_id FROM cru_fr_detail) fd
    JOIN tmp_cru_revision_conversion conv 
      ON fd.cru_revision_id = conv.old_id
     AND conv.new_id <> conv.old_id);

UPDATE cru_frx_revision fr
  JOIN tmp_cru_revision_conversion conv 
    ON fr.cru_revision = conv.old_id
   SET cru_revision = conv.new_id;

-- remove duplicates from cru_revisions

ALTER TABLE cru_revision DROP INDEX uk_crurevision_spr;

UPDATE cru_revision rev
  JOIN tmp_cru_stored_path_conversion conv
    ON rev.cru_path = conv.old_id
   SET rev.cru_path = conv.new_id;

 DELETE
   FROM cru_revision
  WHERE cru_revision_id IN
(SELECT r.cru_revision_id
   FROM (SELECT cru_revision_id FROM cru_revision) r
   JOIN tmp_cru_revision_conversion conv 
     ON r.cru_revision_id = conv.old_id
    AND conv.new_id <> conv.old_id);

ALTER TABLE cru_revision ADD CONSTRAINT uk_crurevision_spr UNIQUE (cru_source_name, cru_path, cru_revision);

-- remove duplicates from cru_stored_path
 
 DELETE
   FROM cru_stored_path
  WHERE cru_path_id IN
(SELECT csp.cru_path_id
   FROM (SELECT cru_path_id FROM cru_stored_path) csp
   JOIN tmp_cru_stored_path_conversion conv
     ON csp.cru_path_id = conv.old_id
    AND conv.new_id <> conv.old_id);

-- recalculate hashes

UPDATE cru_stored_path 
   SET cru_hash = UPPER(SHA2(cru_path, 256));

-- drop conversion tables

DROP TABLE tmp_cru_stored_path_conversion;
DROP TABLE tmp_cru_revision_conversion;
