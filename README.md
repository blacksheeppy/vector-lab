# Vector Raw Logs Lab

Laboratorio reproducible para estudiar una arquitectura centralizada de
ingestión de logs basada en Vector.

El proyecto se construye incrementalmente utilizando Git como registro de la
evolución de la arquitectura. Cada etapa debe dejar el repositorio en un
estado funcional y verificable.

## Objetivo

El primer milestone busca demostrar:

```text
línea generada
    =
línea escrita en archivo
    =
mensaje leído por Vector Agent
    =
mensaje recibido por Vector Gateway
    =
PostgreSQL.raw_message
```

Durante este milestone no se realiza parsing semántico del log.

## Arquitectura

```text
flog
  │
  ▼
logs/app.log
  │
  ▼
Vector Agent
  │
  ├── checkpoint
  └── disk buffer
  │
  │ Vector protocol
  ▼
Vector Gateway
  │
  └── disk buffer
  │
  ▼
PostgreSQL
```

## Versiones

| Componente | Versión |
|---|---:|
| flog | 0.4.0 |
| Vector Agent | 0.57.0 |
| Vector Gateway | 0.57.0 |
| PostgreSQL | 17.10 |

Imágenes:

```text
mingrammer/flog:0.4.0
timberio/vector:0.57.0-debian
postgres:17.10-bookworm
```

## Estructura

```text
vector-raw-logs-lab/
├── README.md
├── .gitignore
├── docker-compose.yml
├── logs/
│   └── .gitkeep
├── vector-agent/
│   └── vector.yaml
├── vector-gateway/
│   └── vector.yaml
└── postgres/
    └── init.sql
```

## Vector Agent

El Agent lee:

```text
/logs/app.log
```

mediante:

```yaml
type: file
```

La línea original queda almacenada en:

```text
.message
```

El Agent mantiene:

```text
file checkpoints
Agent -> Gateway disk buffer
```

dentro de:

```text
/var/lib/vector
```

respaldado por:

```text
vector-agent-data
```

## Vector Gateway

El Gateway recibe eventos utilizando:

```yaml
type: vector
```

El flujo interno es:

```text
Vector source
     │
     ├──────────────► raw console
     │
     ▼
storage_record
     │
     ▼
PostgreSQL disk buffer
     │
     ▼
postgres sink
```

El transform `storage_record` solamente adapta el evento al esquema de
almacenamiento.

No interpreta el Apache Combined Log.

```text
.message   -> raw_message
.file      -> source_file
.host      -> host
.timestamp -> agent_timestamp
```

Además genera:

```text
id
ingested_at
```

## PostgreSQL

Los eventos son almacenados en:

```text
raw_logs
```

con:

```text
id
ingested_at
agent_timestamp
host
source_file
raw_message
```

La propiedad principal continúa siendo:

```text
raw_message == línea original
```

## Persistencia del pipeline

Actualmente existen tres áreas de estado persistente.

### Agent

```text
vector-agent-data
├── file checkpoints
└── Agent -> Gateway disk buffer
```

### Gateway

```text
vector-gateway-data
└── Gateway -> PostgreSQL disk buffer
```

### PostgreSQL

```text
postgres-data
└── raw_logs
```

## Store-and-forward

El pipeline implementa dos etapas de buffering.

```text
FILE
 │
 ▼
Agent
 │
 ├── disk buffer
 │
 ▼
Gateway
 │
 ├── disk buffer
 │
 ▼
PostgreSQL
```

Si el Gateway deja de estar disponible:

```text
FILE
 ↓
Agent disk buffer
 X
Gateway
```

Si PostgreSQL deja de estar disponible:

```text
Agent
 ↓
Gateway
 ↓
Gateway disk buffer
 X
PostgreSQL
```

## PostgreSQL failure

El escenario de esta etapa es:

```text
postgres DOWN

flog
 ↓
file
 ↓
Agent
 ↓
Gateway
 ↓
disk buffer
 X
PostgreSQL
```

Mientras PostgreSQL está detenido:

- flog continúa generando logs;
- el Agent continúa enviando;
- el Gateway continúa recibiendo;
- el raw console continúa mostrando eventos;
- los eventos para PostgreSQL quedan pendientes en el disk buffer;
- Vector continúa intentando recuperar la conexión.

Cuando PostgreSQL vuelve:

```text
Gateway disk buffer
        │
        ▼
       retry
        │
        ▼
   PostgreSQL
```

Los eventos pendientes deben terminar almacenándose en `raw_logs`.

## Backpressure

El disk buffer PostgreSQL utiliza:

```yaml
buffer:
  type: disk
  max_size: 268435488
  when_full: block
```

Si PostgreSQL permanece caído hasta llenar el buffer:

```text
PostgreSQL DOWN
      │
      ▼
Gateway buffer FULL
      │
      ▼
backpressure
      │
      ▼
Agent
```

Debido a que Agent -> Gateway también dispone de buffering, la presión puede
seguir propagándose:

```text
Gateway buffer FULL
        │
        ▼
Agent buffer
        │
        ▼
file source
        │
        ▼
logs/app.log
```

Por lo tanto no existe capacidad infinita.

La retención del archivo original sigue siendo parte de la estrategia de
durabilidad.

## Acknowledgements

Los acknowledgements permiten transferir responsabilidad entre componentes.

Conceptualmente:

```text
Agent
  │
  ▼
Gateway recibe
  │
  ▼
Gateway persiste en disk buffer
  │
  ▼
ACK
  │
  ▼
Agent puede liberar el evento
```

El hecho de que PostgreSQL esté temporalmente caído no obliga al Agent a
mantener el evento indefinidamente si el Gateway ya lo almacenó de forma
durable.

## Delivery semantics

El laboratorio debe tratar el pipeline global como:

```text
at-least-once
```

y no:

```text
exactly-once
```

Por lo tanto:

```text
loss should be minimized
duplicates remain possible
```

No se implementa todavía deduplicación.

## Validación normal

Cantidad:

```sql
SELECT count(*)
FROM raw_logs;
```

Últimos logs:

```sql
SELECT
    ingested_at,
    agent_timestamp,
    host,
    source_file,
    raw_message
FROM raw_logs
ORDER BY ingested_at DESC
LIMIT 20;
```

## Validación de fallo

Detener PostgreSQL:

```bash
docker compose stop postgres
```

Mantener:

```text
log-generator
vector-agent
vector-gateway
```

funcionando.

Después recuperar:

```bash
docker compose start postgres
```

y verificar que el backlog pendiente termine en `raw_logs`.

## Roadmap

1. Inicializar laboratorio. ✅
2. Agregar flog. ✅
3. Agregar Vector Agent. ✅
4. Agregar Vector Gateway. ✅
5. Buffering persistente Agent -> Gateway. ✅
6. Persistir logs RAW en PostgreSQL. ✅
7. Resiliencia Gateway -> PostgreSQL. ← etapa actual
8. Agregar Grafana.
9. Agregar observabilidad del pipeline.
10. Agregar tests reproducibles.
11. Documentar arquitectura.

## Milestone RAW

El milestone busca demostrar:

```text
flog
 ↓
raw line
 ↓
file
 ↓
Vector Agent
 ↓
Vector Gateway
 ↓
PostgreSQL.raw_message
```

cumpliendo:

```text
original_line == raw_message
```

y probando:

```text
checkpoint
buffer
retry
recovery
```

El parsing se incorporará después de completar este milestone.