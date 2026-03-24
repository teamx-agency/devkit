# /teamx-status — Estado Rápido de la Agencia

Muestra un dashboard rápido del estado actual de todos los proyectos activos de TeamX.

## Uso

```
/teamx-status
/teamx-status [PROJECT-ID]
```

---

## Instrucciones para el LLM

### Sin PROJECT-ID — Vista global

1. Usa `teamx_list_projects` para obtener todos los proyectos activos.
2. Para cada proyecto activo (máximo 5 más recientes), usa `teamx_list_project_tasks` con `status: ["in_progress"]`.
3. Presenta el dashboard:

```
# 🏢 TeamX — Estado de la Agencia
Actualizado: [timestamp]

## Proyectos Activos

### 🟢 [Proyecto 1] — [Cliente]
Milestone: [nombre] ([X]% completado)
En progreso: [N] tareas | Blockers: [N]

### 🟡 [Proyecto 2] — [Cliente]  
Milestone: [nombre] ([X]% completado)
En progreso: [N] tareas | Blockers: [N]

### 🔴 [Proyecto 3] — [Cliente] ⚠️ Blocker detectado
[descripción del blocker]
```

### Con PROJECT-ID — Vista detallada del proyecto

1. Usa `teamx_get_project_detail` con el PROJECT-ID.
2. Usa `teamx_get_workflow_state` para el estado del agente.
3. Usa `gitlab_list_pipelines` para el estado de CI/CD.
4. Presenta resumen detallado con pipelines, MRs abiertos y tareas.

---

## Notas

- Usa indicadores visuales: 🟢 en tiempo, 🟡 con riesgo, 🔴 con bloqueo.
- Si no hay proyectos activos, indica que todos están completados o en pausa.
