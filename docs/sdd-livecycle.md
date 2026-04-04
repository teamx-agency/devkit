# SDD Lifecycle: TeamX Agency — Análisis Completo y Roadmap Técnico

> **Última revisión:** 2026-04-04  
> **Propósito:** Documento unificado que cubre el ciclo de vida completo Spec-Driven Development en TeamX Agency, las brechas identificadas frente al framework SDD teórico, y el plan técnico de mejoras con referencias exactas al código.

---

## 1. El Flujo Completo

El ciclo de vida de desarrollo en TeamX Agency opera en tres capas: el **servidor TeamX** (gestión de proyectos, SDD, MCP), el **DevKit** (state machine local, enforcement de gates), y la **capa de experiencia** (persona, rituales, lecciones).

### 1.1 Diagrama del Ciclo Completo

```
┌─────────────────────────────────────────────────────────────────┐
│                    PRE-DEVELOPMENT                               │
│                                                                  │
│  AI Discovery ──► SDD Session (TeamX Server)                    │
│  teamx_start_sdd_session()                                       │
│  teamx_send_sdd_message() × N (Arquitecto IA ↔ Dev)             │
│  teamx_approve_sdd()  ← genera milestones + tasks + AC          │
│                        ↓                                         │
│              extracted_fields → ProjectTasks → AcceptanceCriteria│
└──────────────────────────┬──────────────────────────────────────┘
                           ↓
┌─────────────────────────────────────────────────────────────────┐
│                 DEVELOPMENT CYCLE (DevKit v2)                    │
│                                                                  │
│  IDLE → INIT ─────────────────────────────────────────────────  │
│    teamx_get_project_detail()                                    │
│    teamx_list_sdd_sessions() → extrae tech context              │
│    parsea .gitlab-ci.yml → ci-profile.json                      │
│                        ↓                                         │
│  SELECT → CLASSIFY ───────────────────────────────────────────  │
│    teamx_get_workflow_state()                                    │
│    teamx_transition_task(uuid, "in_progress")                   │
│    Determina work_type → crea branch: feat/<slug>               │
│                        ↓                                         │
│  [PLAN] ──────────────────────────────────────────────────────  │
│    Opcional: >5 archivos, cross-layer, alto riesgo              │
│    ⏱️  Timer implícito: tiempo excesivo = señal SDD débil        │
│                        ↓                                         │
│  IMPLEMENT → VERIFY → COMMIT → PUSH → MR → PIPELINE → MERGE    │
│                        ↓                                         │
│  EVIDENCE (hard gate) ─────────────────────────────────────────  │
│    teamx_satisfy_acceptance_criterion() × N                     │
│    Mapeo explícito: cada AC → archivo:línea                     │
│                        ↓                                         │
│  [RETROSPECTIVE] ──────────────────────────────────────────────  │
│    Captura: qué salió bien, qué fue difícil, patrón aprendido   │
│    Actualiza journal/ → lessons.sh → lessons.json               │
└──────────────────────────┬──────────────────────────────────────┘
                           ↓
┌─────────────────────────────────────────────────────────────────┐
│               POST-DEVELOPMENT (Estado Actual)                   │
│                                                                  │
│  lessons.sh analiza journal/*.json                               │
│  Genera lessons.json (local, solo este devkit)                  │
│  session-start.ts inyecta top 3 patterns en próxima sesión      │
│                                                                  │
│  ❌ NO se envía al servidor TeamX                                │
│  ❌ NO está disponible para otros devkits                        │
└─────────────────────────────────────────────────────────────────┘
```

---

## 2. Comparación con el Framework SDD Teórico

### 2.1 Tabla de Cobertura

| Fase SDD Teórico | Gate DevKit | Herramienta | Estado |
|-----------------|-------------|-------------|--------|
| **Specify** | SDD Session (Server) | `teamx_start_sdd_session`, `teamx_send_sdd_message` | ✅ Cubierto |
| **Gate: Revisión de intención** | SDD Approval | `teamx_approve_sdd` | ✅ Cubierto |
| **Plan** — Tech design | Gate PLAN | State machine + plan humano | ✅ Cubierto |
| **Task Breakdown** | Gate CLASSIFY + tasks en server | `teamx_get_workflow_state` | ✅ Cubierto |
| **Implementation** | Gate IMPLEMENT | Edit/Write enforced por hooks | ✅ Cubierto |
| **Validation** | Gate VERIFY + EVIDENCE | `verify.sh` + AC mapping | ✅ Cubierto |
| **Archive & Update** — Spec viva | Gate RETROSPECTIVE | `lessons.sh` (opcional) | ⚠️ Parcial |
| **Lessons / Engram** — Memoria persistente | `lessons.json` local | `session-start.ts` (solo local) | ❌ No se comparte |
| **Bottleneck detection** | ❌ No existe | — | ❌ Brecha |
| **AC para setup/foundation tasks** | ❌ Quedan sin criterios | `WorkflowSeeder` | ❌ Brecha |
| **SDD como fuente de verdad post-aprobación** | ❌ Edición bloqueada | `SolutionDesignService` | ❌ Brecha crítica |
| **Engram Sync** — Compartir entre devs | ❌ No existe | — | ❌ Brecha |

### 2.2 Fortalezas del Sistema Actual

1. **State machine determinista** — Gates non-negotiable enforced por hooks, no por voluntad del agente
2. **CI real** — `verify.sh` corre los mismos checks del pipeline, sin divergencia mock/prod
3. **Evidencia obligatoria** — EVIDENCE mapea cada AC a código específico (archivo:línea)
4. **Contexto preservado** — `session-start.ts` restaura estado, handoff y lecciones entre sesiones

### 2.3 Brechas Identificadas

**Brecha 1: Tareas sin AC** (setup/foundation/chore)  
`WorkflowSeeder.php:106-130` — tasks sin `story_id` y sin blueprint match quedan con `criteria_status: missing`, bloqueando EVIDENCE en el DevKit.

**Brecha 2: SDD no es fuente de verdad**  
`SolutionDesignService.php:375-377` — throw exception bloquea edición post-aprobación. Cambiar el SDD en UI no actualiza las tareas ni lo que el MCP devuelve.

**Brecha 3: Lecciones siloed**  
`lessons.json` es local por devkit. El conocimiento de un dev no llega a otros. El SDD no recibe retroalimentación del proceso de implementación.

**Brecha 4: Sin detección de cuellos de botella**  
Si un `feature` pasa demasiado tiempo en PLAN, nadie lo captura. Esto es una señal directa de que el SDD original no fue suficientemente específico en esa área.

**Brecha 5: Notifications sin trazabilidad del agente**  
`PostProjectUpdateTool.php` no incluye quién corrió el devkit en el mensaje del canal.

---

## 3. Plan Técnico de Implementación

---

### Feature A: AC Auto-generados para Todas las Tareas

#### Problema Técnico

```php
// WorkflowSeeder.php:110-118 — estado actual
$storyId  = $sddTask['story_id'] ?? null;
$criteria = [];

if ($storyId !== null && isset($storyAcMap[$storyId])) {
    $criteria = $storyAcMap[$storyId];
} elseif (isset($blueprintAcMap[$title])) {
    $criteria = $blueprintAcMap[$title];
}
// Si $criteria === [] → cero AC creados ← bug en tasks de Setup/Foundation
```

#### Implementación

**Archivo:** `plugins/WorkflowEnginePlugin/Services/WorkflowSeeder.php`

**Cambio 1 — línea 118:** Agregar tercer fallback con AC inline del SDD task:

```php
} elseif (!empty($sddTask['acceptance_criteria'])) {
    $criteria = $sddTask['acceptance_criteria'];
}
```

**Cambio 2 — línea 119:** Si `$criteria` sigue vacío, generar criterios mínimos:

```php
if (empty($criteria)) {
    $criteria = $this->generateFallbackCriteria($title, $phase['name'] ?? 'Setup');
}
```

**Nuevo método privado (~línea 256):**

```php
/**
 * Generate minimal fallback criteria for setup/foundation/chore tasks
 * that have no user story or blueprint acceptance criteria.
 *
 * @return array<int, string>
 */
private function generateFallbackCriteria(string $title, string $phaseName): array
{
    return [
        "The task '{$title}' is fully implemented with no errors or warnings.",
        "All CI checks (lint, static analysis, tests) pass after this change.",
        "The implementation is verifiable and documented in the commit message.",
    ];
}
```

---

### Feature B: SDD como Fuente de Verdad (Post-Approval Sync)

#### Problema Técnico

```php
// SolutionDesignService.php:375-377
if (isset($fields['_approved'])) {
    throw new \RuntimeException(
        'El SDD ya fue aprobado y no puede editarse. Inicia una nueva sesion para correcciones.'
    );
}
```

Una vez aprobado el SDD, ninguna edición desde la UI puede propagarse a las tareas existentes. El MCP devuelve los `extracted_fields` originales congelados, no la versión editada.

#### Implementación

**Archivo 1:** `plugins/TeamXPlugin/Services/SolutionDesignService.php`

**Cambio en `updateDecision()`, líneas 375-377:** Remover el throw, detectar si es post-aprobación:

```php
// ANTES: throw new \RuntimeException(...)
// DESPUÉS:
$isPostApproval = isset($fields['_approved']);
// Continúa el flujo normal — se permitirá editar con re-seed automático
```

**Al final de `updateDecision()`, antes del return:** Si es post-aprobación, disparar re-seed:

```php
if ($isPostApproval) {
    $updatedFields = $session->getExtractedFields() ?? [];
    $seederStats   = $this->workflowSeeder->reseed($project, $updatedFields);
    $result['reseeded'] = $seederStats;
}
```

**En el constructor de `SolutionDesignService`:** Verificar si `WorkflowSeeder` ya está inyectado. Si no, agregar:

```php
public function __construct(
    // ... existentes ...
    private readonly WorkflowSeeder $workflowSeeder,
) {}
```

---

**Archivo 2:** `plugins/WorkflowEnginePlugin/Services/WorkflowSeeder.php`

**Nuevo método público `reseed()`** — actualiza AC solo en tasks `todo` sin criterios satisfechos:

```php
/**
 * Re-sync acceptance criteria after a post-approval SDD edit.
 * Only touches tasks in TODO status with zero satisfied criteria.
 *
 * @return array{tasks_updated: int, criteria_updated: int}
 */
public function reseed(Project $project, array $extractedFields): array
{
    $stats = ['tasks_updated' => 0, 'criteria_updated' => 0];

    $phases      = $extractedFields['tasks']['phases'] ?? [];
    $userStories = $extractedFields['spec']['user_stories'] ?? [];

    $storyAcMap     = $this->buildStoryAcMap($userStories);
    $blueprintAcMap = $this->buildBlueprintAcMap($extractedFields);
    $taskByTitle    = $this->buildTaskByTitleMap($project);

    foreach ($phases as $phase) {
        foreach ($phase['tasks'] ?? [] as $sddTask) {
            $title = $sddTask['title'] ?? '';
            $task  = $taskByTitle[$title] ?? null;

            // Only reseed TODO tasks with no satisfied criteria
            if ($task === null || $task->getStatus()->value !== 'todo') {
                continue;
            }
            foreach ($task->getAcceptanceCriteria() as $ac) {
                if ($ac->getIsSatisfied()) {
                    continue 2;
                }
            }

            // Resolve new criteria (same priority as seed())
            $storyId  = $sddTask['story_id'] ?? null;
            $criteria = [];
            if ($storyId !== null && isset($storyAcMap[$storyId])) {
                $criteria = $storyAcMap[$storyId];
            } elseif (isset($blueprintAcMap[$title])) {
                $criteria = $blueprintAcMap[$title];
            } elseif (!empty($sddTask['acceptance_criteria'])) {
                $criteria = $sddTask['acceptance_criteria'];
            }
            if (empty($criteria)) {
                $criteria = $this->generateFallbackCriteria($title, $phase['name'] ?? '');
            }

            // Replace unsatisfied AC with updated ones
            foreach ($task->getAcceptanceCriteria() as $old) {
                $this->em->remove($old);
            }
            $order = 0;
            foreach ($criteria as $scenario) {
                $criterion = new AcceptanceCriterion();
                $criterion->setTask($task);
                $criterion->setDescription($this->resolveScenarioDescription($scenario));
                $criterion->setSortOrder($order++);
                $this->em->persist($criterion);
                $stats['criteria_updated']++;
            }
            $stats['tasks_updated']++;
        }
    }

    $this->em->flush();
    return $stats;
}
```

---

### Feature C: Notifications con DevKit Username

#### Problema Técnico

```php
// PostProjectUpdateTool.php:181-194 — formatMessage() sin username
private function formatMessage(string $message, string $updateType, string $projectCode): string
{
    // ... prefix logic ...
    return "{$prefix}: {$message}";
    // Resultado: "[PRJ-009] Evidence: Task done: ..." — sin identificar al agente
}
```

El `$ctx->principal` (TeamMember ID) ya llega al tool pero solo se usa en el audit log, no en el mensaje visible.

#### Implementación

**Archivo:** `plugins/TeamXPlugin/Tools/PostProjectUpdateTool.php`

**Cambio 1 — en `execute()` tras `unset($args['_ctx'])` (~línea 44):** Resolver username:

```php
$principal  = $ctx?->principal ?? null;
$actorId    = is_numeric($principal) ? (int) $principal : null;
$devkitUser = null;

if ($actorId !== null) {
    $member = $this->em->getRepository(TeamMember::class)->find($actorId);
    if ($member !== null) {
        $devkitUser = $member->getGitlabUsername()
            ?? $member->getTelegramUsername()
            ?? (str_contains($member->getEmail() ?? '', '@')
                ? explode('@', $member->getEmail())[0]
                : null);
    }
}
```

**Cambio 2 — línea 73:** Pasar `$devkitUser` a `formatMessage()`:

```php
$chatMessage->setContent($this->formatMessage($message, $updateType, $projectCode, $devkitUser));
```

**Cambio 3 — `formatMessage()`, línea 181:** Nuevo param + suffix:

```php
private function formatMessage(
    string $message,
    string $updateType,
    string $projectCode,
    ?string $devkitUser = null,
): string {
    $prefix = match ($updateType) {
        'gate_transition' => "[{$projectCode}] Gate transition",
        'task_completed'  => "[{$projectCode}] Task completed",
        'verification'    => "[{$projectCode}] Verification",
        'blocker'         => "[{$projectCode}] Blocker",
        'handoff'         => "[{$projectCode}] Handoff",
        'evidence'        => "[{$projectCode}] Evidence",
        default           => "[{$projectCode}] Status",
    };

    $suffix = $devkitUser !== null ? " (devkit @{$devkitUser})" : '';

    return "{$prefix}: {$message}{$suffix}";
}
```

**Resultado:**
```
[PRJ-009] Evidence: Task done: Launcher.select() con prioridades. MR !12 merged. (devkit @rodrigo)
```

---

### Feature D: lessons.json Compartido via MCP (Propuesta Técnica)

Esta es la extensión al sistema de aprendizaje descrito en la sección 4 y 5.

#### lessons.json v2 — Estructura Ampliada

Sobre los campos actuales (`most_failed_checks`, `work_type_distribution`, `avg_task_duration`), agregar:

```json
{
  "version": 2,
  "project_code": "PRJ-001",
  "analyzed_at": "2026-04-04T19:00:00Z",
  "task_count": 12,
  "bottlenecks": [
    {
      "gate": "PLAN",
      "work_type": "feature",
      "avg_time_hours": 4.2,
      "threshold_hours": 1.5,
      "occurrence_count": 3,
      "signal": "PLAN_OVERTIME_FEATURE",
      "pattern": "SDD insuficientemente específico en contratos de datos",
      "suggested_sdd_action": "Incluir sección de data contracts en SDD para features"
    }
  ],
  "sdd_quality_signals": [
    {
      "signal": "PLAN_OVERTIME_FEATURE",
      "frequency": 3,
      "severity": "high",
      "interpretation": "El SDD no definió contratos de datos con suficiente detalle"
    }
  ]
}
```

**Tabla de triggers de captura:**

| Evento | Umbral | Señal |
|--------|--------|-------|
| `feature` en PLAN > 90 min | Configurable | `PLAN_OVERTIME_FEATURE` |
| `bugfix` falla VERIFY > 2 veces | 2 runs | `VERIFY_MULTI_FAIL` |
| IMPLEMENT modifica archivos no planeados | >3 fuera del scope | `SCOPE_CREEP` |
| EVIDENCE no puede mapear un AC | 1 AC sin evidencia | `AC_UNMAPPABLE` |

**Cambios en DevKit (`teamx-lib/lessons.sh`):**

Agregar lectura de `gate_timestamps` del journal para calcular tiempo por gate y clasificar señales SDD.

#### Nuevas MCP Tools en TeamX Server

**`teamx_push_lessons`** — El DevKit publica su `lessons.json` local al servidor tras completar análisis:

```typescript
teamx_push_lessons({
  project_code: "PRJ-001",
  lessons: { version: 2, bottlenecks: [...], sdd_quality_signals: [...] }
})
```

**`teamx_get_shared_lessons`** — `session-start.ts` consulta lecciones agregadas del equipo:

```typescript
teamx_get_shared_lessons({
  project_code: "PRJ-001",
  topics: ["PLAN", "feature"],
  limit: 5
})
// Retorna: shared_lessons[] con señales normalizadas de todo el equipo
```

**Flujo de retroalimentación al SDD:**

```
SDD Session (pre-dev)
      ↓
Implementación → PLAN overtime → lessons.json v2
                                       ↓
                         teamx_push_lessons() → Server agrega señal
                                       ↓
                    Próxima SDD session recibe señales históricas
                    y el spec-shaper hace preguntas más específicas
```

---

## 4. Roadmap de Implementación

### Prioridad 1 — Inmediata (sin nuevas dependencies)

| # | Feature | Archivos | Esfuerzo |
|---|---------|----------|---------|
| C | Notification username | `PostProjectUpdateTool.php` (3 cambios) | 1h |
| A | AC fallback para setup/foundation | `WorkflowSeeder.php` (+fallback, +método) | 1h |

### Prioridad 2 — Ciclo siguiente

| # | Feature | Archivos | Esfuerzo |
|---|---------|----------|---------|
| B | SDD post-approval sync | `SolutionDesignService.php` + `WorkflowSeeder.php` (reseed) | 3h |

### Prioridad 3 — Mediano plazo

| # | Feature | Archivos | Esfuerzo |
|---|---------|----------|---------|
| D1 | lessons.json v2 con bottlenecks | `teamx-lib/lessons.sh` | 2h |
| D2 | `teamx_push_lessons` MCP tool | Server: nueva tool + tabla `devkit_lessons` | 4h |
| D3 | `teamx_get_shared_lessons` MCP tool | Server: aggregation logic + session-start.ts | 3h |
| D4 | Retroalimentación al SDD | `StartSddSessionTool.php` + prompts | 2h |

---

## 5. Verificación

### Feature A (AC fallback)
```bash
# Crear SDD con fases Setup/Foundation sin story_id, aprobar, luego:
# teamx_get_task_detail(uuid) → acceptance_criteria debe ser no-vacío
# criteria_status debe ser "pending", no "missing"
```

### Feature B (SDD sync)
```bash
# 1. Aprobar SDD → editar user story AC en UI → verificar 200 (no excepción)
# 2. teamx_get_task_detail(uuid tarea todo) → AC deben reflejar edición
# 3. teamx_get_task_detail(uuid tarea done) → AC NO modificados
```

### Feature C (Notification username)
```bash
# teamx_post_project_update con principal autenticado
# → mensaje en canal debe terminar: "(devkit @rodrigo)"
# → sin principal: mensaje sin sufijo (degradación graceful)
```

### PHPStan + Tests
```bash
./vendor/bin/phpstan analyse plugins/WorkflowEnginePlugin plugins/TeamXPlugin --level=6
./vendor/bin/phpunit
```
