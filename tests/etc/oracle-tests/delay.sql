DECLARE
    in_time number := 3;
BEGIN
    DBMS_LOCK.sleep(in_time);
END;