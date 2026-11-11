import { flushPromises, mount } from '@vue/test-utils'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import App from '../App.vue'

const seed = [
  { id: 1, title: '把代码推上 Git', done: 1, created_at: '2026-11-11 10:00:00' },
  { id: 2, title: '让流水线自动构建', done: 0, created_at: '2026-11-11 10:01:00' }
]

function okJson(data) {
  return { ok: true, status: 200, json: async () => data }
}

describe('App.vue', () => {
  beforeEach(() => {
    global.fetch = vi.fn()
  })

  afterEach(() => {
    vi.restoreAllMocks()
  })

  it('加载并渲染任务列表', async () => {
    global.fetch.mockResolvedValueOnce(okJson(seed))
    const wrapper = mount(App)
    await flushPromises()

    expect(wrapper.findAll('.item')).toHaveLength(2)
    expect(wrapper.text()).toContain('把代码推上 Git')
    expect(wrapper.text()).toContain('1/2 已完成')
  })

  it('加载失败时展示错误提示', async () => {
    global.fetch.mockResolvedValueOnce({ ok: false, status: 500 })
    const wrapper = mount(App)
    await flushPromises()

    expect(wrapper.find('.error').text()).toContain('加载任务失败')
  })

  it('提交新任务后重新加载列表', async () => {
    global.fetch
      .mockResolvedValueOnce(okJson(seed))
      .mockResolvedValueOnce(okJson({ id: 3, title: '新任务' }))
      .mockResolvedValueOnce(okJson([...seed, { id: 3, title: '新任务', done: 0, created_at: '2026-11-11 11:00:00' }]))

    const wrapper = mount(App)
    await flushPromises()

    await wrapper.find('input').setValue('新任务')
    await wrapper.find('form').trigger('submit')
    await flushPromises()

    expect(global.fetch).toHaveBeenCalledTimes(3)
    expect(wrapper.findAll('.item')).toHaveLength(3)
  })

  it('点击删除按钮会发起 DELETE 请求', async () => {
    global.fetch
      .mockResolvedValueOnce(okJson(seed))
      .mockResolvedValueOnce({ ok: true, status: 204 })
      .mockResolvedValueOnce(okJson([seed[0]]))

    const wrapper = mount(App)
    await flushPromises()

    await wrapper.find('.remove').trigger('click')
    await flushPromises()

    const [url, options] = global.fetch.mock.calls[1]
    expect(url).toContain('/tasks/1')
    expect(options.method).toBe('DELETE')
    expect(wrapper.findAll('.item')).toHaveLength(1)
  })
})
