-- drop the conversion tables if they already exist for some reason. They shouldn't exist yet but it's a good check
BEGIN
    EXECUTE IMMEDIATE 'drop table tmp_cru_stored_path_conversion';

    EXECUTE IMMEDIATE 'drop table tmp_cru_revision_conversion';
EXCEPTION
    WHEN OTHERS THEN
      NULL;
END;

/
-- dropping cru_source_rev_path_hash
-- reverts the db to previous state before upgrade
BEGIN
    EXECUTE IMMEDIATE
    'alter table cru_revision drop column cru_source_rev_path_hash';
EXCEPTION
    WHEN OTHERS THEN
      NULL;
END;

/
-- drop the unique constraint, if it exists, for now. it is added back later
DECLARE
    name VARCHAR2(200);
BEGIN
    --we need to explicitly query the constraint name, because it can either be 'uk_crurevision_spr' if upgraded, or it's unnamed and has an automatically generated 'SYS_C*' name if it's a fresh install
    SELECT constraint_name
    INTO   name
    FROM   all_constraints
           NATURAL join all_cons_columns
    WHERE  table_name = 'CRU_REVISION'
           AND column_name = 'CRU_PATH'
           AND constraint_type = 'U';

    EXECUTE IMMEDIATE 'ALTER TABLE CRU_REVISION DROP CONSTRAINT '|| name;
EXCEPTION
    WHEN no_data_found THEN
      NULL;
END;

/
-- create conversion tables
BEGIN
    EXECUTE IMMEDIATE
    'create table tmp_cru_stored_path_conversion (new_id int, old_id int)';

    EXECUTE IMMEDIATE
    'create table tmp_cru_revision_conversion (new_id int, old_id int)';
END;

/
-- re-point the dependencies and delete the dupes
DECLARE
    -- create cursors. I hate cursors, but oracle merge won't let you modify fields in the 'on' clause, and since we're modifying the identifier linking the tables, I'm not sure of a better way
    CURSOR cpr_cursor IS
      SELECT conv.new_id,
             conv.old_id
      FROM   cru_patch_revision pr
             join tmp_cru_revision_conversion conv
               ON pr.cru_revision_id = conv.old_id;
    CURSOR cfm_cursor IS
      SELECT conv.new_id,
             conv.old_id
      FROM   cru_feindex_msg fm
             join tmp_cru_revision_conversion conv
               ON fm.cru_fr_id = conv.old_id;
    CURSOR cfr_cursor IS
      SELECT conv.new_id,
             conv.old_id
      FROM   cru_frx_revision fr
             join tmp_cru_revision_conversion conv
               ON fr.cru_revision = conv.old_id;
    CURSOR cpath_cursor IS
      SELECT conv.new_id,
             conv.old_id
      FROM   cru_revision rev
             join tmp_cru_stored_path_conversion conv
               ON rev.cru_path = conv.old_id;
BEGIN
    -- populate conversion tables
    INSERT INTO tmp_cru_stored_path_conversion
                (old_id,
                 new_id)
    SELECT sp.cru_path_id old_id,
           tmp.min_id     new_id
    FROM   (SELECT Min(cru_path_id) min_id,
                   cru_path
            FROM   cru_stored_path
            GROUP  BY cru_path) tmp
           join cru_stored_path sp
             ON tmp.cru_path = sp.cru_path;

    -- second insert into tmp_cru_stored_path_conversion to handle where the path is null
    INSERT INTO tmp_cru_stored_path_conversion
                (old_id,
                 new_id)
    SELECT cru_path_id,
           (SELECT Min(csp_min.cru_path_id)
            FROM   cru_stored_path csp_min
            WHERE  cru_path IS NULL) min_id
    FROM   cru_stored_path
    WHERE  cru_path IS NULL
    GROUP  BY cru_path_id;

    -- proceed to populating tmp_cru_revision_conversion
    INSERT INTO tmp_cru_revision_conversion
                (new_id,
                 old_id)
    (SELECT tmp.min_id,
            rev.cru_revision_id
     FROM   cru_revision rev
            join tmp_cru_stored_path_conversion spconv
              ON rev.cru_path = spconv.old_id
            join (SELECT Min(rev.cru_revision_id) min_id,
                         rev.cru_source_name,
                         spconv.new_id,
                         rev.cru_revision
                  FROM   cru_revision rev
                         join tmp_cru_stored_path_conversion spconv
                           ON rev.cru_path = spconv.old_id
                  GROUP  BY rev.cru_source_name,
                            spconv.new_id,
                            rev.cru_revision) tmp
              ON tmp.cru_source_name = rev.cru_source_name
                 AND tmp.new_id = spconv.new_id
                 AND tmp.cru_revision = rev.cru_revision);

    -- update cru_revision dependencies
    FOR cpr_record IN cpr_cursor LOOP
        UPDATE cru_patch_revision cpr
        SET    cpr.cru_revision_id = cpr_record.new_id
        WHERE  cpr.cru_revision_id = cpr_record.old_id;
    END LOOP;

    FOR cfm_record IN cfm_cursor LOOP
        UPDATE cru_feindex_msg cfm
        SET    cfm.cru_fr_id = cfm_record.new_id
        WHERE  cfm.cru_fr_id = cfm_record.old_id;
    END LOOP;

    DELETE FROM cru_fr_detail
    WHERE  cru_revision_id IN (SELECT fd.cru_revision_id
                               FROM   cru_fr_detail fd
                                      join tmp_cru_revision_conversion conv
                                        ON fd.cru_revision_id = conv.old_id
                                           AND conv.new_id <> conv.old_id);

    FOR cfr_record IN cfr_cursor LOOP
        UPDATE cru_frx_revision cfr
        SET    cfr.cru_revision = cfr_record.new_id
        WHERE  cfr.cru_revision = cfr_record.old_id;
    END LOOP;

    -- remove duplicates from cru_revisions
    FOR cpath_record IN cpath_cursor LOOP
        UPDATE cru_revision
        SET    cru_path = cpath_record.new_id
        WHERE  cru_path = cpath_record.old_id;
    END LOOP;

    DELETE FROM cru_revision
    WHERE  cru_revision_id IN (SELECT r.cru_revision_id
                               FROM   cru_revision r
                                      join tmp_cru_revision_conversion conv
                                        ON r.cru_revision_id = conv.old_id
                                           AND conv.new_id <> conv.old_id);

    -- bring back the 'uk_crurevision_spr' constraint.
    EXECUTE IMMEDIATE 'alter table cru_revision
add constraint uk_crurevision_spr
unique (cru_source_name, cru_path, cru_revision)';

    -- remove duplicates from cru_stored_path
    DELETE FROM cru_stored_path
    WHERE  cru_path_id IN(SELECT csp.cru_path_id
                          FROM   cru_stored_path csp
                                 join tmp_cru_stored_path_conversion conv
                                   ON csp.cru_path_id = conv.old_id
                                      AND conv.new_id <> conv.old_id);
END;

/
-- recalculate hashes
BEGIN
    UPDATE cru_stored_path
    SET    cru_hash = Standard_hash(cru_path, 'SHA256');
END;

/
-- drop conversion tables
BEGIN
    EXECUTE IMMEDIATE 'drop table tmp_cru_stored_path_conversion';

    EXECUTE IMMEDIATE 'drop table tmp_cru_revision_conversion';
END;

/ 