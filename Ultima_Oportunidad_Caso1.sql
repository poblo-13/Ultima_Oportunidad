-- 1 CASO 1
CREATE OR REPLACE TRIGGER trg_actualizar_totales
AFTER INSERT OR UPDATE OR DELETE ON consumo
FOR EACH ROW
BEGIN
    -- opcion 1 se inserta un nuevo consumo
    IF INSERTING THEN
        UPDATE total_consumos
        SET monto_consumos = monto_consumos + :NEW.monto
        WHERE id_huesped = :NEW.id_huesped;
        
        -- si el huesped no existia en la tabla de totales se crea su registro inicial
        IF SQL%ROWCOUNT = 0 THEN
            INSERT INTO total_consumos (id_huesped, monto_consumos)
            VALUES (:NEW.id_huesped, :NEW.monto);
        END IF;
        
    -- opcion1 se actualiza un consumo existente
    ELSIF UPDATING THEN
        IF :OLD.id_huesped = :NEW.id_huesped THEN
            -- se compensa la diferencia en el mismo huesped
            UPDATE total_consumos
            SET monto_consumos = (monto_consumos - :OLD.monto) + :NEW.monto
            WHERE id_huesped = :NEW.id_huesped;
        ELSE
            -- si se cambia el ID del huesped se ajustan ambos saldos por separado
            UPDATE total_consumos SET monto_consumos = monto_consumos - :OLD.monto WHERE id_huesped = :OLD.id_huesped;
            UPDATE total_consumos SET monto_consumos = monto_consumos + :NEW.monto WHERE id_huesped = :NEW.id_huesped;
        END IF;

    -- opcion 3 se elimina un consumo
    ELSIF DELETING THEN
        UPDATE total_consumos
        SET monto_consumos = monto_consumos - :OLD.monto
        WHERE id_huesped = :OLD.id_huesped;
    END IF;
END;
/

-- 2 BLOQUE DE PRUEBA 
DECLARE
    v_next_id NUMBER;
BEGIN
    -- obtenemos la ID siguiente de forma parametrica
    SELECT NVL(MAX(id_consumo), 0) + 1 INTO v_next_id FROM consumo;
    
    -- op 1 insertar nuevo consumo
    INSERT INTO consumo (id_consumo, id_reserva, id_huesped, monto) VALUES (v_next_id, 1587, 340006, 150);
    
    -- op 2 eliminar consumo con ID 11473
    DELETE FROM consumo WHERE id_consumo = 11473;
    
    -- op 3 actualizar monto a ID 10688
    UPDATE consumo SET monto = 95 WHERE id_consumo = 10688;
    
    COMMIT;
END;
/

-- 3 VERIFICACION
SELECT * FROM total_consumos 
WHERE id_huesped IN (340006, 340004, 340008) 
ORDER BY id_huesped;