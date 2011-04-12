assert = require 'assert'
url = require 'url'

chain = (require 'slide').chain
asyncMap = (require 'slide').asyncMap

rest = require 'grouper-rest'
storage = require 'storage'
StackFactory = storage.StackFactory
fixtures = require '../resources/fixtures'


server = null
tableName = (conf, suffix) ->
  prefix = conf.get "general:prefix"
  if not prefix then assert.fail()
  return prefix + suffix;

hbaseClient = (conf) ->
  restUrl = conf.get "storage:hbase:rest"
  if not restUrl then assert.fail()
  parts = url.parse restUrl;
  return require('hbase') {'host': parts.hostname, 'port': parts.port}


setup = (require 'config') 'test/resources/testconf.json', (err, conf) ->
  factory = new StackFactory conf
  factory.push (require 'storage').hbase.factory
  factory.build (store) ->
    client = hbaseClient conf
    list = for tableId, contents of fixtures
      [load, client, (tableName conf, tableId), contents]

    startServer = ->
      rest.start conf, (up, s) ->
        if up then throw up
        server = s
        for k, t of tests
          exports[k] = t

    chain list, (err, success) ->
      if err then throw err
      startServer()


load = (client, tableName, contents, cb) ->
  "Load the passed contents into the given table."
  puts = []

  putNested = (value, cKey) ->
    if typeof(cell) == "string" or typeof(cell) == "number"
      puts.push {key: key, column: cKey, '$': cell}
    else
      for ts, value of cell
        puts.push {key: key, column: cKey, timestamp: ts, '$': value}

  for key, families of contents
    for family, columns of families
      for qualifier, cell of columns
        putNested cell, [family, qualifier].join(':')

  table = client.getRow tableName, null
  table.put puts, (err, success) ->
    if err then return cb(err)
    return cb(null, success)


tests =
  'test GET doc': (beforeExit) ->
    req = {method: 'GET', url: '/docs/will/mid/doc3'}
    check = (res) ->
      doc = (JSON.parse res.body)
      assert.eql doc.id, "doc3"
      assert.eql doc.text, fixtures.documents["will/mid/doc3"].main.text
    assert.response server, req, {status: 200}, check

  'test GET one cluster': (beforeExit) ->
    req = {method: 'GET', url: '/clusters/will/mid/macbeth'}
    expected = ["doc3", "doc4", "doc5"]
    check = (res) ->
      actual = (JSON.parse res.body).sort()
      assert.eql actual, expected
    assert.response server, req, {status: 200}, check

  'test GET all clusters A': ->
    req = {method: 'GET', url: '/clusters/will/mid'}
    check = (res) ->
      assert.response server, req, {status: 200}
      all = JSON.parse res.body
      assert.ok ("macbeth" of all)
      assert.ok ("caesar" of all)
      assert.ok ("general" of all)
      assert.eql all["macbeth"].length, 3
      assert.eql all["caesar"].length, 2
      assert.eql all["general"].length, 2
    assert.response server, req, check

  'test GET all clusters B': ->
    req = {method: 'GET', url: '/clusters/will/tail'}
    check = (res) ->
      assert.response server, req, {status: 200}
      all = JSON.parse res.body
      assert.ok ("macbeth" in all)

  'test GET single cluster not found': ->
    req = {method: 'GET', url: '/clusters/will/mid/avenue-q'}
    assert.response server, req, {status: 404}
    req = {method: 'GET', url: '/clusters/will/no-such-coll/macbeth'}
    assert.response server, req, {status: 404}

  'test GET clusters for collection not found': ->
    req = {method: 'GET', url: '/clusters/will/no-such-coll'}
    assert.response server, req, {status: 404}

  'test POST doc': ->
    req =
      method: 'POST'
      url: '/collections/will/lear'
      data: JSON.stringify {id: '10', text: 'Have more than thou showest'}
    assert.response server, req, {body: "/docs/will/lear/10"}
    req =
      method: 'POST'
      url: '/collections/will/lear'
      data: JSON.stringify {id: '11', text: 'Speak less than thou knowest'}
    assert.response server, req, {body: "/docs/will/lear/11"}

other =
  'test POST doc to invalid collections': ->
    req =
      method: 'POST'
      url: '/collections//my-collection'
      data: JSON.stringify {id: '11', text: 'Speak less than thou knowest'}
    assert.response server, req, {status: 404}
    req =
      method: 'POST'
      url: '/collections/will/'
      data: JSON.stringify {id: '11', text: 'Speak less than thou knowest'}
    assert.response server, req, {status: 404}

exports = module.exports = {}
