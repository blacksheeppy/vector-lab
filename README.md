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
raw_message almacenado
```

Durante este milestone no se realizará parsing semántico de los logs.

## Arquitectura objetivo

```text
flog
  │
  │ genera logs
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

### Vector Agent

El Agent estará orientado a:

```text
collection
checkpoint
buffer
retry
transport
```

### Vector Gateway

El Gateway permitirá centralizar:

```text
reception
buffering
routing
storage delivery
```

Durante el primer milestone no interpretará semánticamente el contenido
de los logs.

### PostgreSQL

PostgreSQL almacenará inicialmente:

```text
raw_message
+
transport metadata
```

El contenido original del log deberá conservarse sin parsing.

## Principios del laboratorio

- Cada etapa corresponde aproximadamente a un commit funcional.
- Ningún commit debe dejar intencionalmente rota la infraestructura.
- Las imágenes de contenedores utilizan versiones explícitas.
- No se utiliza la etiqueta `latest`.
- Las opciones específicas de Vector se verifican contra la versión utilizada.
- No se realizará parsing antes de validar el pipeline RAW end-to-end.
- Los cambios serán revisados antes de realizar cada commit.

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

Las instancias Vector utilizan:

```text
timberio/vector:0.57.0-debian
```

## Estado actual

El pipeline implementado actualmente es:

```text
flog
  │
  ▼
logs/app.log
  │
  ▼
Vector Agent
  │
  │ Vector protocol
  ▼
Vector Gateway
  │
  ▼
stdout
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
└── vector-gateway/
    └── vector.yaml
```

Durante la ejecución, `flog` crea:

```text
logs/app.log
```

Este archivo es runtime data y no se almacena en Git.

## Generador de logs

El servicio:

```text
log-generator
```

utiliza `flog` para generar continuamente logs Apache Combined.

Puede observarse desde el host:

```bash
tail -f logs/app.log
```

## Vector Agent

El servicio:

```text
vector-agent
```

lee:

```text
/logs/app.log
```

utilizando:

```yaml
type: file
```

Cada línea se conserva inicialmente en:

```text
.message
```

No existen transforms ni parsing.

El Agent envía el evento al Gateway utilizando el protocolo nativo de Vector:

```text
file source
    │
    ▼
Vector event
    │
    ▼
vector sink
    │
    ▼
Vector Gateway
```

El endpoint configurado es:

```text
http://vector-gateway:6000
```

El Agent conserva sus checkpoints en:

```text
/var/lib/vector
```

respaldado por:

```text
vector-agent-data
```

## Vector Gateway

El servicio:

```text
vector-gateway
```

escucha eventos Vector en:

```text
0.0.0.0:6000
```

mediante:

```yaml
type: vector
```

Actualmente su única salida es un sink:

```yaml
type: console
```

con:

```yaml
encoding:
  codec: raw_message
```

Por lo tanto el Gateway imprime solamente:

```text
.message
```

sin realizar parsing ni transformaciones.

## Flujo RAW actual

```text
logs/app.log
        │
        ▼
Vector Agent
        │
        │ .message
        ▼
Vector protocol
        │
        ▼
Vector Gateway
        │
        │ .message
        ▼
stdout
```

La propiedad que queremos demostrar en esta etapa es:

```text
logs/app.log line
        =
Agent .message
        =
Gateway .message
```

## Metadata

El protocolo Vector transporta el evento Vector completo, no solamente
`.message`.

El evento generado originalmente por el file source contiene metadata como:

```text
message
file
host
timestamp
source_type
```

Al atravesar el source `vector` del Gateway, `source_type` representa ahora al
source receptor y pasa a identificar a Vector.

Por lo tanto no utilizaremos `source_type` como identificador del origen
original cuando incorporemos almacenamiento.

Los campos relevantes para ese propósito serán principalmente:

```text
host
file
```

mientras que:

```text
message
```

continuará siendo la línea RAW que debemos preservar.

## Buffering

En esta etapa no se configura todavía un disk buffer para el transporte
Agent -> Gateway.

Tampoco se configura explícitamente end-to-end acknowledgement.

Estas capacidades se incorporarán y probarán en la siguiente etapa para poder
demostrar su comportamiento de forma controlada.

## Validación

Observar el archivo original:

```bash
tail -f logs/app.log
```

Observar lo recibido por el Gateway:

```bash
docker compose logs -f vector-gateway
```

Observar warnings o errores del Agent:

```bash
docker compose logs -f vector-agent
```

El criterio principal es:

```text
línea en app.log == línea mostrada por vector-gateway
```

## Roadmap

1. Inicializar el laboratorio. ✅
2. Agregar `flog` como generador de logs. ✅
3. Agregar Vector Agent leyendo el archivo local. ✅
4. Agregar Vector Gateway. ← etapa actual
5. Validar buffering y recuperación Agent → Gateway.
6. Persistir logs RAW en PostgreSQL.
7. Validar recuperación Gateway → PostgreSQL.
8. Agregar visualización con Grafana.
9. Agregar observabilidad del pipeline Vector.
10. Agregar escenarios reproducibles de prueba.
11. Documentar la arquitectura alcanzada.

## Milestone 1 — RAW pipeline

El primer milestone estará completo cuando podamos demostrar:

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

y habiendo probado capacidades básicas de:

```text
checkpoint
buffer
retry
recovery
```

El parsing y la normalización se incorporarán únicamente después de alcanzar
este milestone.