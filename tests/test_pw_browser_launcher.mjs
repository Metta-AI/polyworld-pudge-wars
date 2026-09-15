import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { runInNewContext } from 'node:vm'
import test from 'node:test'

const client = 'https://pudge-build.example/play/pw.html'
const shell = readFileSync(new URL('../examples/pudge_wars/coworld_player.html', import.meta.url), 'utf8')
const script = shell.match(/<script>([\s\S]*?)<\/script>/)[1].replace('__WASM_CLIENT_URL__', JSON.stringify(client))

function launch(href) {
  let destination
  runInNewContext(script, { URL, window: { location: { href, replace: (url) => { destination = new URL(url) } } } })
  return destination
}

test('hosted player keeps the proxy prefix and seat credentials', () => {
  const address = 'wss://game.example/v2/coworlds/play/session/ps_test/proxy/player?slot=0&token=a%2Bb%26c'
  const result = launch(`https://game.example/v2/coworlds/play/session/ps_test/proxy/client/player?address=${encodeURIComponent(address)}`)
  assert.equal(result.origin + result.pathname, client)
  assert.equal(result.searchParams.get('join'), 'wss://game.example/v2/coworlds/play/session/ps_test/proxy/ws')
  assert.equal(result.searchParams.get('slot'), '0')
  assert.equal(result.searchParams.get('token'), 'a+b&c')
})

test('Observatory episode player keeps the job proxy and seat credentials', () => {
  const address = 'wss://game.example/v2/coworlds/jobs/00000000-0000-0000-0000-000000000010/proxy/player?slot=0&token=a%2Bb%26c'
  const result = launch(`https://game.example/v2/coworlds/jobs/00000000-0000-0000-0000-000000000010/proxy/client/player?address=${encodeURIComponent(address)}`)
  assert.equal(result.origin + result.pathname, client)
  assert.equal(result.searchParams.get('join'), 'wss://game.example/v2/coworlds/jobs/00000000-0000-0000-0000-000000000010/proxy/ws')
  assert.equal(result.searchParams.get('slot'), '0')
  assert.equal(result.searchParams.get('token'), 'a+b&c')
})

test('spectators connect without claiming a player seat', () => {
  const address = 'wss://game.example/v2/coworlds/play/session/ps_test/proxy/global'
  const result = launch(`https://game.example/client/global?address=${encodeURIComponent(address)}`)
  assert.equal(result.searchParams.get('join'), 'wss://game.example/v2/coworlds/play/session/ps_test/proxy/ws')
  assert.equal(result.searchParams.has('token'), false)
  assert.equal(result.searchParams.has('slot'), false)
})

test('local direct player links preserve seat zero and names', () => {
  const result = launch('http://localhost:8789/client/player?slot=0&token=local&name=Aaron')
  assert.equal(result.searchParams.get('join'), 'ws://localhost:8789/ws')
  assert.equal(result.searchParams.get('slot'), '0')
  assert.equal(result.searchParams.get('name'), 'Aaron')
})
