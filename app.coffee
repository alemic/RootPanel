#!/usr/bin/env coffee

{EventEmitter} = require 'events'

global.app = module.exports = new EventEmitter()

app.libs =
  _: require 'underscore'
  fs: require 'fs'
  path: require 'path'
  jade: require 'jade'
  async: require 'async'
  crypto: require 'crypto'
  moment: require 'moment-timezone'
  request: require 'request'
  express: require 'express'
  child_process: require 'child_process'

  csrf: require 'csrf'
  mongoose: require 'mongoose'
  mongooseUniqueValidator: require 'mongoose-unique-validator'
  jsonStableStringify: require 'json-stable-stringify'
  Negotiator: require 'negotiator'
  ObjectID: (require 'mongoose').Types.ObjectId
  ObjectId: (require 'mongoose').Schema.Types.ObjectId
  Mixed: (require 'mongoose').Schema.Types.Mixed

cookieParser = require 'cookie-parser'
BunyanMongo = require 'bunyan-mongo'
bodyParser = require 'body-parser'
nodemailer = require 'nodemailer'
Insight = require 'insight'
morgan = require 'morgan'
Mabolo = require 'mabolo'
bunyan = require 'bunyan'
redis = require 'redis'
harp = require 'harp'

{_, fs, path, express} = app.libs

app.package = require './package'
config = require './config'
utils = require './core/utils'

fs.chmodSync path.join(__dirname, 'config.coffee'), 0o750

if fs.existsSync config.web.listen
  fs.unlinkSync config.web.listen

insight = new Insight
  # 这个代码用于向 RootPanel 开发者提交匿名的统计信息
  # This code used to send anonymous usage metrics to RootPanel developers
  # 您不必修改这里 You do not have to modify it
  trackingCode: 'UA-49193300-7'
  packageName: app.package.name
  packageVersion: app.package.version

insight.track 'app.coffee'

redis = redis.createClient 6379, '127.0.0.1',
  auth_pass: config.redis.password

mailer = nodemailer.createTransport config.email.account

mabolo = new Mabolo utils.mongodbUri _.extend config.mongodb,
  name: config.mongodb.test

bunyanMongo = new BunyanMongo()

mabolo.on 'connected', bunyanMongo.setDB.bind bunyanMongo

logger = bunyan.createLogger
  name: app.package.name
  streams: [
    type: 'raw'
    level: 'info'
    stream: bunyanMongo
  ,
    level: process.env.LOG_LEVEL ? 'debug'
    stream: process.stdout
  ]

_.extend app,
  utils: utils
  redis: redis
  config: config
  mabolo: mabolo
  mailer: mailer
  logger: logger
  models: mabolo.models
  insight: insight
  express: express()

app.db = require './core/db'
app.i18n = require './core/i18n'
app.cache = require './core/cache'
app.pluggable = require './core/pluggable'

require './core/model/Account'
require './core/model/Financials'
require './core/model/CouponCode'
require './core/model/Notification'
require './core/model/SecurityLog'
require './core/model/Ticket'
require './core/model/Component'

app.templates = require './core/templates'
app.billing = require './core/billing'
app.middleware = require './core/middleware'
app.notification = require './core/notification'

app.interfaces =
  Node: require './core/interface/Node'
  Plan: require './core/interface/Plan'
  ComponentTemplate: require './core/interface/ComponentTemplate'
  Plugin: require './core/interface/Plugin'

app.express.use bodyParser.json()
app.express.use cookieParser()

app.express.use app.middleware.session()
app.express.use app.middleware.logger()
app.express.use app.middleware.errorHandling
app.express.use app.middleware.csrf()
app.express.use app.middleware.authenticate
app.express.use app.middleware.accountHelpers

app.express.set 'views', path.join __dirname, 'core/view'
app.express.set 'view engine', 'jade'

app.express.use '/component', require './core/router/component'
app.express.use '/account', require './core/router/account'
app.express.use '/billing', require './core/router/billing'
app.express.use '/ticket', require './core/router/ticket'
app.express.use '/coupon', require './core/router/coupon'
app.express.use '/admin', require './core/router/admin'
app.express.use '/panel', require './core/router/panel'

app.i18n.init()
app.billing.initPlans()
app.pluggable.initPlugins()

app.nodes = {}

for name, info of config.nodes
  app.nodes[name] = new app.interfaces.Node _.extend info,
    name: name

app.express.use '/bower_components', express.static './bower_components'
app.express.use harp.mount './core/static'

app.express.get '/', (req, res) ->
  res.redirect '/panel/'

exports.start = _.once ->
  app.express.listen config.web.listen, ->
    if fs.existsSync config.web.listen
      fs.chmodSync config.web.listen, 0o770

    app.started = true
    app.logger.info "RootPanel start at #{config.web.listen}"
    app.emit 'app.started'

unless module.parent
  exports.start()
