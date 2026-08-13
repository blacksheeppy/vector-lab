-- ---------------------------------------------------------------------------
-- Vector Raw Logs Lab
-- PostgreSQL initialization
-- ---------------------------------------------------------------------------
--
-- Esta tabla almacena exclusivamente:
--
--   - la línea RAW original;
--   - metadata de transporte generada por Vector.
--
-- NO contiene campos derivados del contenido Apache.
--
-- No existen todavía:
--
--   method
--   status
--   path
--   remote_addr
--
-- El parsing se incorporará solamente después de validar el milestone RAW.
-- ---------------------------------------------------------------------------


CREATE TABLE raw_logs (
    -- Identificador de la fila de almacenamiento.
    --
    -- Vector genera este UUID antes de enviar el evento al sink PostgreSQL.
    id UUID PRIMARY KEY,

    -- Momento en que el Gateway preparó el evento para persistencia.
    --
    -- No representa necesariamente el instante exacto del COMMIT SQL.
    ingested_at TIMESTAMPTZ NOT NULL,

    -- Timestamp agregado originalmente por el file source del Agent.
    --
    -- Representa el instante en que Vector ingirió la línea del archivo.
    agent_timestamp TIMESTAMPTZ NOT NULL,

    -- Host que realizó la colección.
    host TEXT NOT NULL,

    -- Archivo desde el cual el Agent obtuvo la línea.
    source_file TEXT NOT NULL,

    -- Línea original generada por flog.
    --
    -- Este campo es la propiedad fundamental del milestone:
    --
    --   raw_message == línea original
    raw_message TEXT NOT NULL
);


-- Este índice facilitará las consultas cronológicas del laboratorio y,
-- posteriormente, los paneles de Grafana.
CREATE INDEX raw_logs_ingested_at_idx
    ON raw_logs (ingested_at DESC);