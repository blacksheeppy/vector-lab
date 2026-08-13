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
  ├── checkpoint
  ├── disk buffer
  ├── retry
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

mediante:

```yaml
type: file
```

Cada línea se conserva en:

```text
.message
```

No existen transforms ni parsing.

El Agent envía eventos al Gateway utilizando el protocolo nativo de Vector:

```text
file source
    │
    ▼
disk buffer
    │
    ▼
vector sink
    │
    ▼
Vector Gateway
```

## Estado persistente del Agent

Vector utiliza:

```text
/var/lib/vector
```

como `data_dir`.

Docker Compose monta allí el named volume:

```text
vector-agent-data
```

Este directorio contiene estado operacional persistente como:

```text
file checkpoints
disk buffers
```

Por lo tanto:

```text
vector-agent container
       X
       │ restart
       ▼
vector-agent-data
       │
       ├── checkpoints
       └── disk buffer
```

continúa existiendo.

## Disk buffer

El transporte Agent -> Gateway utiliza:

```yaml
buffer:
  type: disk
  max_size: 268435488
  when_full: block
```

El disk buffer permite conservar eventos pendientes cuando el Gateway no está
temporalmente disponible.

`when_full: block` significa que si el buffer alcanza su capacidad, Vector
aplica backpressure hacia los componentes anteriores en vez de descartar
deliberadamente eventos nuevos.

En esta arquitectura eso termina trasladando el backlog hacia el borde:

```text
logs/app.log
```

si el Agent ya no puede continuar consumiendo.

## Retries

El sink `vector` dispone de retry automático para errores recuperables.

No se modifican todavía sus parámetros predeterminados.

Conceptualmente:

```text
send
 │
 ├── success ───────────────► continuar
 │
 └── failure
       │
       ▼
     retry
       │
       ▼
     backoff
       │
       ▼
     retry
```

## Acknowledgements

El sink `vector` del Agent tiene:

```yaml
acknowledgements:
  enabled: true
```

El file source soporta acknowledgements, pero no configuramos esta propiedad
directamente en el source.

El Gateway habilita acknowledgements en su console sink.

La cadena actual es:

```text
file source
    │
    ▼
Agent disk buffer
    │
    ▼
vector sink
    │
    ▼
vector source
    │
    ▼
Gateway console
    │
    ▼
ACK
```

En esta etapa:

```text
ACK
=
evento procesado por el console sink del Gateway
```

Todavía NO significa:

```text
ACK
=
evento persistido en PostgreSQL
```

PostgreSQL será incorporado posteriormente.

## Checkpoints

El file source mantiene checkpoints dentro del `data_dir`.

Los checkpoints permiten reanudar la lectura de archivos previamente
descubiertos después de reiniciar el Agent.

Es importante distinguir:

```text
checkpoint
```

de:

```text
disk buffer
```

El checkpoint responde:

```text
¿hasta dónde avancé en el archivo?
```

El disk buffer responde:

```text
¿qué eventos aceptados todavía tengo pendientes de entregar?
```

Ambos estados son persistentes en este laboratorio.

## Fallo del Gateway

El escenario esperado es:

```text
flog
  │
  ▼
app.log
  │
  ▼
Agent
  │
  ▼
disk buffer
  │
  X
Gateway
```

Mientras el Gateway está detenido:

- flog continúa escribiendo;
- el Agent continúa leyendo mientras tenga capacidad;
- los eventos pendientes se almacenan en el disk buffer;
- el sink intenta recuperar la conexión;
- no se utiliza `drop_newest`.

Cuando el Gateway vuelve:

```text
disk buffer
    │
    ▼
retry
    │
    ▼
Gateway
    │
    ▼
backlog entregado
```

## Reinicio del Agent

También queremos validar:

```text
Gateway DOWN
     │
     ▼
Agent acumula backlog
     │
     ▼
restart Agent
     │
     ▼
checkpoint + disk buffer sobreviven
     │
     ▼
Gateway UP
     │
     ▼
backlog recuperado
```

Esto permite diferenciar dos mecanismos:

```text
checkpoint = posición de lectura
buffer     = eventos pendientes de entrega
```

## Garantía de entrega

El objetivo es acercarnos a una semántica:

```text
at-least-once
```

y no:

```text
exactly-once
```

Un evento puede potencialmente volver a enviarse en determinadas condiciones
de fallo.

Por eso una arquitectura durable debe asumir que:

```text
duplicates are possible
```

y diseñar el almacenamiento posterior en consecuencia.

## Límites de la durabilidad

El disk buffer mejora la durabilidad, pero no significa que cada byte que haya
entrado en memoria sea inmediatamente crash-safe.

Vector sincroniza periódicamente el buffer a disco.

Además:

```text
when_full: block
```

no crea capacidad infinita.

Cuando el buffer se llena, el backlog debe acumularse en el origen.

En este laboratorio el origen es:

```text
logs/app.log
```

Por eso la preservación completa también depende de que el archivo no sea
eliminado o rotado antes de que Vector pueda consumirlo.

## Validación RAW

La propiedad de las etapas anteriores continúa siendo:

```text
logs/app.log line
        =
Agent .message
        =
Gateway .message
```

El buffering no debe modificar el contenido del evento.

## Roadmap

1. Inicializar el laboratorio. ✅
2. Agregar `flog` como generador de logs. ✅
3. Agregar Vector Agent leyendo el archivo local. ✅
4. Agregar Vector Gateway. ✅
5. Validar buffering y recuperación Agent → Gateway. ← etapa actual
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