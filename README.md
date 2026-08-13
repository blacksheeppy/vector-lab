# Vector Raw Logs Lab

Laboratorio reproducible para estudiar una arquitectura centralizada de
ingestión de logs basada en Vector.

El proyecto se construye incrementalmente utilizando Git como registro de la
evolución de la arquitectura. Cada etapa debe dejar el repositorio en un
estado funcional y verificable.

## Objetivo

El primer milestone del laboratorio busca demostrar el transporte y
almacenamiento de una línea de log sin modificar su contenido.

La propiedad fundamental que queremos validar es:

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

Durante este milestone no se realiza parsing semántico de los logs.

## Arquitectura objetivo

```text
flog
  │
  ▼
archivo .log
  │
  ▼
Vector Agent
  │
  │ Vector protocol
  ▼
Vector Gateway
  │
  ▼
PostgreSQL
  │
  ▼
Grafana
```

## Principios del laboratorio

- Cada etapa corresponde aproximadamente a un commit funcional.
- Ningún commit debe dejar intencionalmente rota la infraestructura.
- Las imágenes de contenedores utilizan versiones explícitas.
- No se utiliza la etiqueta `latest`.
- Las opciones específicas de Vector se verifican contra la versión utilizada.
- No se realiza parsing antes de validar el pipeline RAW end-to-end.
- Los cambios se revisan antes de realizar cada commit.

## Requisitos

Para trabajar con el laboratorio se necesita:

- Git.
- Docker Engine.
- Docker Compose plugin.
- Acceso al daemon de Docker.
- Acceso a un registry de contenedores.

La instalación puede verificarse con:

```bash
git --version
docker version
docker compose version
```

## Versiones utilizadas

| Componente | Versión |
|---|---:|
| flog | 0.4.0 |
| Vector Agent | 0.57.0 |
| Vector Gateway | 0.57.0 |
| PostgreSQL | 17.10 |

Las imágenes utilizadas son:

```text
mingrammer/flog:0.4.0
timberio/vector:0.57.0-debian
postgres:17.10-bookworm
```

## Estado actual

El pipeline implementado es:

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
  ├── disk buffer
  └── retry
  │
  │ Vector protocol
  ▼
Vector Gateway
  │
  ├── raw console
  │
  └── storage projection
          │
          ▼
      PostgreSQL
```

Estructura:

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

## Generador de logs

`log-generator` utiliza `flog` para generar continuamente Apache Combined.

El archivo puede observarse desde el host:

```bash
tail -f logs/app.log
```

## Vector Agent

El Agent lee:

```text
/logs/app.log
```

utilizando:

```yaml
type: file
```

La línea original queda almacenada en:

```text
.message
```

El Agent conserva:

```text
checkpoint
disk buffer
```

bajo:

```text
/var/lib/vector
```

respaldado por el volumen:

```text
vector-agent-data
```

El transporte hacia el Gateway utiliza el protocolo nativo de Vector.

## Vector Gateway

El Gateway recibe eventos mediante:

```yaml
type: vector
```

en:

```text
0.0.0.0:6000
```

La entrada se divide actualmente en dos ramas:

```text
                 ┌──► raw console
Agent ─► Gateway │
                 └──► storage_record ─► PostgreSQL
```

### Raw console

Esta salida imprime solamente:

```text
.message
```

y permite continuar comparando el evento recibido contra el archivo original.

### Storage projection

Para insertar en PostgreSQL se utiliza un pequeño transform:

```text
.message   → raw_message
.file      → source_file
.host      → host
.timestamp → agent_timestamp
```

También agrega:

```text
id
ingested_at
```

Este transform NO interpreta el contenido del log.

No existen todavía campos como:

```text
method
status
path
remote_addr
```

## PostgreSQL

PostgreSQL almacena los eventos en:

```text
raw_logs
```

con el esquema lógico:

```text
id
ingested_at
agent_timestamp
host
source_file
raw_message
```

### raw_message

Es una copia directa de:

```text
.message
```

y debe permanecer igual a la línea producida originalmente por flog.

### agent_timestamp

Representa el timestamp generado por el file source cuando la línea fue
ingerida por el Agent.

No representa el timestamp contenido dentro del Apache log.

### ingested_at

Representa el momento en que el Gateway preparó el evento para persistencia.

No debe interpretarse como el instante exacto de COMMIT de PostgreSQL.

### id

Es un UUID generado por el Gateway para identificar la fila almacenada.

Actualmente no se utiliza como mecanismo de deduplicación end-to-end.

## Limitación del sink PostgreSQL

Vector utiliza internamente `jsonb_populate_recordset` para insertar eventos.

Por este motivo, los defaults PostgreSQL no se comportan como se esperaría
para campos ausentes del evento.

Por ejemplo, no dependemos de:

```sql
id BIGSERIAL
```

ni:

```sql
ingested_at TIMESTAMPTZ DEFAULT now()
```

En su lugar el Gateway construye explícitamente todos los campos requeridos
por la tabla.

## Flujo RAW

```text
flog
  │
  ▼
raw line
  │
  ▼
logs/app.log
  │
  ▼
Vector Agent
  │
  │ .message
  ▼
Vector Gateway
  │
  │ .message
  ▼
storage_record
  │
  │ raw_message = .message
  ▼
PostgreSQL.raw_logs
```

La propiedad principal de esta etapa es:

```text
original_line == PostgreSQL.raw_message
```

## Consultas

Cantidad total:

```sql
SELECT count(*)
FROM raw_logs;
```

Últimos eventos:

```sql
SELECT
    id,
    ingested_at,
    agent_timestamp,
    host,
    source_file,
    raw_message
FROM raw_logs
ORDER BY ingested_at DESC
LIMIT 20;
```

Solamente las líneas RAW:

```sql
SELECT raw_message
FROM raw_logs
ORDER BY ingested_at DESC
LIMIT 20;
```

## Persistencia

PostgreSQL utiliza el volumen Docker:

```text
postgres-data
```

El Agent utiliza:

```text
vector-agent-data
```

Por lo tanto existen actualmente dos estados persistentes independientes:

```text
vector-agent-data
    ├── checkpoints
    └── Agent disk buffer

postgres-data
    └── PostgreSQL database
```

## Estado de resiliencia

Agent -> Gateway ya dispone de:

```text
checkpoint
disk buffer
retry
acknowledgements
```

Gateway -> PostgreSQL todavía NO dispone de un disk buffer persistente
configurado explícitamente.

La resiliencia frente a una caída de PostgreSQL será validada en el próximo
commit.

## Roadmap

1. Inicializar el laboratorio. ✅
2. Agregar flog como generador. ✅
3. Agregar Vector Agent. ✅
4. Agregar Vector Gateway. ✅
5. Agregar buffering persistente Agent -> Gateway. ✅
6. Persistir logs RAW en PostgreSQL. ← etapa actual
7. Validar recuperación Gateway -> PostgreSQL.
8. Agregar Grafana.
9. Agregar observabilidad del pipeline.
10. Agregar tests reproducibles.
11. Documentar la arquitectura final del milestone.

## Milestone 1

El milestone estará completo cuando podamos demostrar:

```text
flog
  │
  ▼
raw line
  │
  ▼
file
  │
  ▼
Vector Agent
  │
  ▼
Vector Gateway
  │
  ▼
PostgreSQL.raw_message
```

cumpliendo:

```text
original_line == raw_message
```

y habiendo probado:

```text
checkpoint
buffer
retry
recovery
```

El parsing se incorporará únicamente después de completar este milestone.