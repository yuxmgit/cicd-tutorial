<script setup>
import { computed, onMounted, ref } from 'vue'

const API_BASE = import.meta.env.VITE_API_BASE || '/api'

const tasks = ref([])
const loading = ref(true)
const error = ref('')
const title = ref('')
const submitting = ref(false)

const doneCount = computed(() => tasks.value.filter((t) => t.done).length)
const progress = computed(() =>
  tasks.value.length === 0 ? 0 : Math.round((doneCount.value / tasks.value.length) * 100)
)

async function load() {
  loading.value = true
  error.value = ''
  try {
    const res = await fetch(`${API_BASE}/tasks`)
    if (!res.ok) throw new Error(`HTTP ${res.status}`)
    tasks.value = await res.json()
  } catch (e) {
    error.value = `加载任务失败：${e.message}`
  } finally {
    loading.value = false
  }
}

async function addTask() {
  const value = title.value.trim()
  if (!value || submitting.value) return
  submitting.value = true
  error.value = ''
  try {
    const res = await fetch(`${API_BASE}/tasks`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ title: value })
    })
    if (!res.ok) throw new Error(`HTTP ${res.status}`)
    title.value = ''
    await load()
  } catch (e) {
    error.value = `添加任务失败：${e.message}`
  } finally {
    submitting.value = false
  }
}

async function removeTask(id) {
  error.value = ''
  try {
    const res = await fetch(`${API_BASE}/tasks/${id}`, { method: 'DELETE' })
    if (!res.ok && res.status !== 204) throw new Error(`HTTP ${res.status}`)
    await load()
  } catch (e) {
    error.value = `删除任务失败：${e.message}`
  }
}

onMounted(load)
</script>

<template>
  <main class="page">
    <section class="card">
      <header class="card-head">
        <div>
          <h1>任务清单</h1>
          <p class="subtitle">CI/CD 教程示例 · 每次提交都会自动走到这里</p>
        </div>
        <span class="badge">{{ doneCount }}/{{ tasks.length }} 已完成</span>
      </header>

      <div class="progress" role="progressbar" :aria-valuenow="progress" aria-valuemin="0" aria-valuemax="100">
        <div class="progress-bar" :style="{ width: progress + '%' }"></div>
      </div>

      <form class="add-form" @submit.prevent="addTask">
        <input
          v-model="title"
          type="text"
          maxlength="100"
          placeholder="下一件要做的事…"
          aria-label="新任务标题"
        />
        <button type="submit" :disabled="submitting || !title.trim()">
          {{ submitting ? '添加中…' : '添加' }}
        </button>
      </form>

      <p v-if="error" class="error" role="alert">{{ error }}</p>

      <p v-if="loading" class="hint">正在加载…</p>
      <p v-else-if="tasks.length === 0" class="hint">还没有任务，先添加一条吧。</p>

      <ul v-else class="list">
        <li v-for="task in tasks" :key="task.id" class="item">
          <span class="dot" :class="{ done: task.done }"></span>
          <span class="title">{{ task.title }}</span>
          <time class="time">{{ task.created_at }}</time>
          <button class="remove" type="button" :aria-label="`删除 ${task.title}`" @click="removeTask(task.id)">
            ×
          </button>
        </li>
      </ul>
    </section>

    <footer class="foot">
      <span>Vue 3 + Vite</span>
      <span>·</span>
      <span>FastAPI + SQLite</span>
      <span>·</span>
      <span>Jenkins 流水线部署</span>
    </footer>
  </main>
</template>
