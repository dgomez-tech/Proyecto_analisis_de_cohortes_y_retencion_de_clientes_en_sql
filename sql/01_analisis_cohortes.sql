-- =====================================================================
-- PROYECTO: ANÁLISIS DE COHORTES Y RETENCIÓN DE CLIENTES
-- Base de datos: DuckDB
-- =====================================================================

-- Paso 1: Fecha de primera compra de cada cliente (su cohorte)
CREATE OR REPLACE TABLE cohortes_base AS 
SELECT 
    cliente_id,
    DATE_TRUNC('month', MIN(fecha)) AS cohorte,
    MIN(fecha) AS primera_compra
FROM pedidos
WHERE estado = 'completado' AND cliente_id IS NOT NULL
GROUP BY cliente_id;

-- Verificar la distribución de clientes por cohorte
SELECT 
    cohorte, 
    COUNT(*) AS clientes
FROM cohortes_base
GROUP BY cohorte
ORDER BY cohorte;

select * from cohortes_base limit 10;

-- Paso 2: Actividad mensual + distancia desde la cohorte
CREATE OR REPLACE TABLE actividad_mensual AS
SELECT DISTINCT
    cb.cliente_id,
    cb.cohorte,
    DATE_TRUNC('month', p.fecha) AS mes_actividad,
    DATEDIFF('month', cb.cohorte, DATE_TRUNC('month', p.fecha)) AS meses_desde_inicio
FROM cohortes_base cb
JOIN pedidos p ON p.cliente_id = cb.cliente_id
WHERE p.estado = 'completado' AND p.cliente_id IS NOT NULL
  AND DATEDIFF('month', cb.cohorte, DATE_TRUNC('month', p.fecha)) >= 0;

select * from actividad_mensual limit 10;

-- paso 3: Construir matriz de retención
WITH tamano_cohorte AS (
    SELECT cohorte, COUNT(DISTINCT cliente_id) AS clientes_iniciales
    FROM cohortes_base
    GROUP BY cohorte
),
retencion AS (
    SELECT
        am.cohorte,
        am.meses_desde_inicio,
        COUNT(DISTINCT am.cliente_id) AS clientes_activos
    FROM actividad_mensual am
    GROUP BY am.cohorte, am.meses_desde_inicio
)
SELECT
    r.cohorte,
    tc.clientes_iniciales,
    r.meses_desde_inicio,
    r.clientes_activos,
    ROUND(100.0 * r.clientes_activos / tc.clientes_iniciales, 1) AS pct_retencion
FROM retencion r
JOIN tamano_cohorte tc ON tc.cohorte = r.cohorte
WHERE r.meses_desde_inicio <= 6  -- Primeros 6 meses
ORDER BY r.cohorte, r.meses_desde_inicio;

-- =====================================================================
-- Paso 4: Enriquecer con window functions (Tendencia y Media)
-- =====================================================================

WITH tamano_cohorte AS (
    SELECT cohorte, COUNT(DISTINCT cliente_id) AS n
    FROM cohortes_base GROUP BY cohorte
),
retencion AS (
    SELECT
        am.cohorte, am.meses_desde_inicio,
        COUNT(DISTINCT am.cliente_id) AS activos,
        ROUND(100.0 * COUNT(DISTINCT am.cliente_id) / MAX(tc.n), 1) AS pct
    FROM actividad_mensual am
    JOIN tamano_cohorte tc ON tc.cohorte = am.cohorte
    GROUP BY am.cohorte, am.meses_desde_inicio
)
SELECT
    cohorte,
    meses_desde_inicio,
    pct AS retencion_pct,
    LAG(pct) OVER (PARTITION BY cohorte ORDER BY meses_desde_inicio) AS pct_mes_anterior,
    pct - LAG(pct) OVER (PARTITION BY cohorte ORDER BY meses_desde_inicio) AS caida_vs_anterior,
    ROUND(AVG(pct) OVER (PARTITION BY meses_desde_inicio), 1) AS media_todas_cohortes
FROM retencion
WHERE meses_desde_inicio <= 6
ORDER BY cohorte, meses_desde_inicio;

-- =====================================================================
-- Paso 5: Métricas ejecutivas derivadas
-- =====================================================================

-- Métrica 1: Retención promedio al mes 1 (la más crítica)
SELECT 
    ROUND(AVG(pct_mes_1), 1) AS retencion_promedio_mes_1
FROM (
    SELECT 
        am.cohorte,
        ROUND(100.0 * COUNT(DISTINCT am.cliente_id) / MAX(tc.n), 1) AS pct_mes_1
    FROM actividad_mensual am
    JOIN ( 
        SELECT cohorte, COUNT(DISTINCT cliente_id) AS n 
        FROM cohortes_base 
        GROUP BY cohorte 
    ) tc ON tc.cohorte = am.cohorte
    WHERE am.meses_desde_inicio = 1
    GROUP BY am.cohorte
);


-- Métrica 2: Mejor y peor cohorte basadas en la retención del mes 1
WITH retention_m1 AS (
    SELECT 
        am.cohorte,
        ROUND(100.0 * COUNT(DISTINCT am.cliente_id) / MAX(tc.n), 1) AS pct
    FROM actividad_mensual am
    JOIN ( 
        SELECT cohorte, COUNT(DISTINCT cliente_id) AS n 
        FROM cohortes_base 
        GROUP BY cohorte 
    ) tc ON tc.cohorte = am.cohorte
    WHERE am.meses_desde_inicio = 1
    GROUP BY am.cohorte
)
SELECT 
    cohorte, 
    pct AS retencion_mes_1,
    RANK() OVER (ORDER BY pct DESC) AS rank_mejor,
    RANK() OVER (ORDER BY pct ASC) AS rank_peor
FROM retention_m1
ORDER BY pct DESC;
