# Vector Raw Logs Lab

Laboratorio reproducible para estudiar una arquitectura centralizada de ingestión de logs basada en Vector.

El proyecto se construye incrementalmente utilizando Git como registro de la evolución de la arquitectura. Cada etapa debe dejar el repositorio en un estado funcional y verificable.

## Objetivo

El primer milestone del laboratorio busca demostrar el transporte y almacenamiento de una línea de log sin modificar su contenido.

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

Durante el primer milestone no interpretará semánticamente el contenido de los logs.

### PostgreSQL

PostgreSQL almacenará inicialmente:

```text
raw_message
+
transport metadata
```

El contenido original del log deberá conservarse sin parsing.

## Principios del laboratorio

* Cada etapa corresponde aproximadamente a un commit funcional.
* Ningún commit debe dejar intencionalmente rota la infraestructura.
* Las imágenes de contenedores utilizarán versiones explícitas.
* No se utilizará la etiqueta `latest`.
* Las opciones específicas de Vector deberán verificarse contra la versión utilizada.
* No se realizará parsing antes de validar el pipeline RAW end-to-end.
* Los cambios serán revisados antes de realizar cada commit.

## Requisitos

Para trabajar con el laboratorio se necesita:

* Git.
* Docker Engine.
* Docker Compose plugin.
* Acceso al daemon de Docker.
* Acceso a un registry de contenedores para las etapas posteriores.

La instalación puede verificarse con:

```bash
git --version
docker version
docker compose version
```

## Estado actual

El repositorio se encuentra en su etapa inicial.

Todavía no existen servicios Docker definidos.

```text
vector-raw-logs-lab/
├── README.md
├── .gitignore
└── docker-compose.yml
```

El objetivo de esta etapa es comprobar que Docker Compose puede cargar correctamente la configuración base antes de agregar componentes.

## Roadmap

1. Inicializar el laboratorio.
2. Agregar `flog` como generador de logs.
3. Agregar Vector Agent leyendo el archivo local.
4. Agregar Vector Gateway.
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

El parsing y la normalización se incorporarán únicamente después de alcanzar este milestone.
