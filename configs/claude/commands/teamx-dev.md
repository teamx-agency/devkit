# /teamx-dev — TeamX Project Context Loader

Carga el contexto completo de un proyecto de la agencia y prepara el entorno de trabajo.

## Uso

```
/teamx-dev <PROJECT-ID> [contexto adicional]
```

**Ejemplos:**
```
/teamx-dev TX-42
/teamx-dev TX-42 Trabajando en el módulo de pagos, sprint 3
/teamx-dev TX-42 Implementar CLABE validation según criterios del milestone 2
```

---

## Instrucciones para el LLM

Cuando este comando sea invocado con un PROJECT-ID, debes ejecutar las siguientes acciones **en orden** usando las herramientas del MCP de TeamX:

### 1. Cargar contexto del proyecto
Usa `teamx_get_project_detail` con el PROJECT-ID proporcionado para obtener:
- Nombre y descripción del proyecto
- Cliente y stack tecnológico
- Milestones activos y su progreso
- Equipo asignado

### 2. Obtener estado del workflow
Usa `teamx_get_workflow_state` para conocer:
- Tareas en progreso actualmente
- Blockers o dependencias pendientes
- Último estado registrado del agente

### 3. Listar tareas del sprint activo
Usa `teamx_list_project_tasks` con filtro `status: ["in_progress", "todo"]` para mostrar:
- Tareas prioritarias pendientes
- Criterios de éxito de cada tarea
- Asignaciones actuales

### 4. Obtener contexto del repositorio
Usa `gitlab_get_repo_context` para obtener:
- URL del repositorio
- Branch principal y branches activos
- Último pipeline y su estado

### 5. Presentar resumen
Presenta un resumen estructurado con:

```
## 📋 Proyecto: [Nombre]
**Cliente:** [Cliente] | **Stack:** [Stack]

## 🎯 Sprint Activo — Milestone: [Milestone Name]
Progreso: [X/Y tareas completadas]

## ⚡ En Progreso
- [ ] TX-XX: [Tarea] (Criterio: [criterio de éxito])
- [ ] TX-XX: [Tarea]

## 📥 Próximas (Todo)
- [ ] TX-XX: [Tarea] — Prioridad: [Alta/Media/Baja]

## 🔀 Repositorio
Branch activo: [branch] | Pipeline: [status]

## 🤖 Estado del Agente
[Último estado del workflow]
```

### 6. Preguntar al usuario
Después del resumen, pregunta:

> ¿En qué tarea quieres que me enfoque? Puedo cargar el detalle completo, los criterios de éxito, y el historial del repositorio para esa tarea específica.

---

## Comportamiento esperado

- Si el PROJECT-ID no existe, informa al usuario y lista los proyectos disponibles con `teamx_list_projects`.
- Si hay contexto adicional en el comando, úsalo para pre-filtrar las tareas relevantes.
- Mantén el contexto del proyecto cargado durante toda la sesión para no repetir llamadas al MCP innecesariamente.
- Al transicionar tareas, usa siempre `teamx_transition_task` o `teamx_batch_transition_tasks` y confirma con el usuario antes de ejecutar.
