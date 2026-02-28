-- CASO 2
-- 1 ESTRUCTURA DE PACKAGE PARA CALCULO DE TOURS
CREATE OR REPLACE PACKAGE pkg_cobros_hotel IS
    FUNCTION fn_calcular_tours(p_id_huesped NUMBER) RETURN NUMBER;
END pkg_cobros_hotel;
/

CREATE OR REPLACE PACKAGE BODY pkg_cobros_hotel IS
    FUNCTION fn_calcular_tours(p_id_huesped NUMBER) RETURN NUMBER IS
        v_monto_tours NUMBER := 0;
    BEGIN
        SELECT NVL(SUM(t.valor_tour * ht.num_personas), 0)
        INTO v_monto_tours
        FROM huesped_tour ht
        JOIN tour t ON ht.id_tour = t.id_tour
        WHERE ht.id_huesped = p_id_huesped;
        RETURN v_monto_tours;
    END fn_calcular_tours;
END pkg_cobros_hotel;
/

-- 2 FUNCION DE AGENCIA MANEJO DE ERRORES
CREATE OR REPLACE FUNCTION fn_agencia(p_id_huesped NUMBER) RETURN VARCHAR2 IS
    v_nom_agencia VARCHAR2(50);
    v_id_error NUMBER;
    PRAGMA AUTONOMOUS_TRANSACTION; 
BEGIN
    SELECT a.nom_agencia INTO v_nom_agencia
    FROM huesped h JOIN agencia a ON h.id_agencia = a.id_agencia
    WHERE h.id_huesped = p_id_huesped;
    RETURN v_nom_agencia;
EXCEPTION
    WHEN NO_DATA_FOUND THEN
        SELECT sq_error.NEXTVAL INTO v_id_error FROM DUAL;
        INSERT INTO reg_errores (id_error, nomsubprograma, msg_error)
        VALUES (v_id_error, 'Error en FN_AGENCIA - ID Huesped: ' || p_id_huesped, 'ORA-01403: No se han encontrado datos');
        COMMIT;
        RETURN 'NO REGISTRA AGENCIA';
END fn_agencia;
/

-- 3 FUNCION PARA OBTENER CONSUMOS DESDE LA TABLA DE TOTALES
CREATE OR REPLACE FUNCTION fn_get_consumo_total(p_id_huesped NUMBER) RETURN NUMBER IS
    v_total NUMBER;
BEGIN
    SELECT monto_consumos INTO v_total FROM total_consumos WHERE id_huesped = p_id_huesped;
    RETURN v_total;
EXCEPTION
    WHEN NO_DATA_FOUND THEN RETURN 0;
END fn_get_consumo_total;
/

-- 4 PROCEDIMIENTO PRINCIPAL DE FACTURACION
CREATE OR REPLACE PROCEDURE sp_procesar_facturacion(p_fecha DATE, p_valor_dolar NUMBER) IS
    CURSOR c_checkout IS
        SELECT r.id_reserva, r.id_huesped, r.estadia,
               h.nom_huesped, h.appat_huesped, h.apmat_huesped,
               SUM(hab.valor_habitacion) AS total_hab,
               SUM(hab.valor_minibar) AS total_minibar,
               NVL((SELECT SUM(num_personas) FROM huesped_tour WHERE id_huesped = r.id_huesped), 1) as cant_personas
        FROM reserva r
        JOIN huesped h ON r.id_huesped = h.id_huesped
        JOIN detalle_reserva dr ON r.id_reserva = dr.id_reserva
        JOIN habitacion hab ON dr.id_habitacion = hab.id_habitacion
        WHERE (r.ingreso + r.estadia) = p_fecha
        GROUP BY r.id_reserva, r.id_huesped, r.estadia, h.nom_huesped, h.appat_huesped, h.apmat_huesped;

    v_nombre_completo VARCHAR2(100);
    v_agencia         VARCHAR2(50);
    v_consumos_usd    NUMBER;
    v_pct_desc_con    NUMBER;
    
    v_alojamiento_clp    NUMBER;
    v_cobro_personas_clp NUMBER;
    v_consumos_clp       NUMBER;
    v_tours_clp          NUMBER;
    v_subtotal_clp       NUMBER;
    v_desc_con_clp       NUMBER;
    v_desc_age_clp       NUMBER;
    v_total_final        NUMBER;
BEGIN
    -- limpieza según requerimiento
    EXECUTE IMMEDIATE 'TRUNCATE TABLE detalle_diario_huespedes';
    EXECUTE IMMEDIATE 'TRUNCATE TABLE reg_errores';

    FOR reg IN c_checkout LOOP
        v_nombre_completo := reg.nom_huesped || ' ' || reg.appat_huesped || ' ' || reg.apmat_huesped;
        v_agencia         := fn_agencia(reg.id_huesped);
        v_consumos_usd    := fn_get_consumo_total(reg.id_huesped);
        
        -- calculos base en pesos
        v_alojamiento_clp    := ROUND((reg.total_hab + reg.total_minibar) * reg.estadia * p_valor_dolar);
        v_cobro_personas_clp := reg.cant_personas * 35000;
        v_consumos_clp       := ROUND(v_consumos_usd * p_valor_dolar);
        v_tours_clp          := ROUND(pkg_cobros_hotel.fn_calcular_tours(reg.id_huesped) * p_valor_dolar);
        
        v_subtotal_clp := v_alojamiento_clp + v_cobro_personas_clp + v_consumos_clp;
        
        -- dcto tramos consumos
        BEGIN
            SELECT pct / 100 INTO v_pct_desc_con FROM tramos_consumos
            WHERE v_consumos_usd BETWEEN vmin_tramo AND vmax_tramo;
        EXCEPTION WHEN NO_DATA_FOUND THEN v_pct_desc_con := 0;
        END;
        v_desc_con_clp := ROUND(v_consumos_clp * v_pct_desc_con);
        
        -- dcto agencia 12% viaje alberti
        IF UPPER(v_agencia) = 'VIAJES ALBERTI' THEN
            v_desc_age_clp := ROUND(v_subtotal_clp * 0.12);
        ELSE
            v_desc_age_clp := 0;
        END IF;
        
        v_total_final := (v_subtotal_clp - v_desc_con_clp - v_desc_age_clp) + v_tours_clp;

        INSERT INTO detalle_diario_huespedes (
            id_huesped, nombre, agencia, alojamiento, consumos, tours,
            subtotal_pago, descuento_consumos, descuentos_agencia, total
        ) VALUES (
            reg.id_huesped, v_nombre_completo, v_agencia, v_alojamiento_clp, v_consumos_clp, v_tours_clp,
            v_subtotal_clp, v_desc_con_clp, v_desc_age_clp, v_total_final
        );
    END LOOP;
    COMMIT;
END sp_procesar_facturacion;
/

-- 5 EJECUCION Y REPORTES
BEGIN
    sp_procesar_facturacion(TO_DATE('18/08/2021', 'DD/MM/YYYY'), 915);
END;
/

SET LINESIZE 300;
SET PAGESIZE 100;
SET FEEDBACK OFF;
COLUMN NOMBRE FORMAT A35;
COLUMN AGENCIA FORMAT A25;

PROMPT ==========================================================
PROMPT --- INFORME DE DETALLE DIARIO DE HUESPEDES  ---
PROMPT ==========================================================

SELECT id_huesped, nombre, agencia, alojamiento, consumos, subtotal_pago, descuento_consumos, descuentos_agencia, total
FROM detalle_diario_huespedes 
ORDER BY id_huesped;

PROMPT 
PROMPT ==========================================================
PROMPT --- INFORME DE REGISTRO DE ERRORES          ---
PROMPT ==========================================================

SELECT id_error, nomsubprograma, msg_error 
FROM reg_errores 
ORDER BY id_error;