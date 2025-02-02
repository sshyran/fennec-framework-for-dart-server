part of fennec;

class Server {
  late Application application;

  late HttpServer? _httpServer;
  bool _listeningToServer = false;
  static final Server _instance = Server._internal();

  factory Server(Application application) {
    _instance.application = application;

    return _instance;
  }
  Server._internal();
  Duration? requestTimeOut;
  void setRequestTimeOut(Duration duration) {
    _instance.requestTimeOut = duration;
  }

  final StreamController<UpgradedWebSocket> _webSocketStream =
      StreamController();
  StreamController<UpgradedWebSocket> get webSocketStream => _webSocketStream;
  final StreamController<UpgradedWebSocket> _webSocketStreamBroadcast =
      StreamController();
  StreamController<UpgradedWebSocket> get webSocketStreamBroadcast =>
      _webSocketStreamBroadcast;
  HttpServer get httpServer => _instance._httpServer == null
      ? throw Exception("you should start first")
      : _instance._httpServer!;
  Future<ServerInfo> startServer() async {
    _registerRoutes();
    RoutesHandler.checkRoutes(_registredRoutes);

    if (_instance.application.numberOfIsolates == 1) {
      return isolateServer(false);
    }
    for (int i = 1; i < _instance.application.numberOfIsolates; i++) {
      Isolate.spawn(isolateServer, true);
    }
    return isolateServer(true);
  }

  Future<ServerInfo> isolateServer(bool shared) async {
    _instance._httpServer = await HttpServer.bind(
        application.host, application.port,
        shared: shared);
    final ServerInfo _serverInfo = ServerInfo(
        _instance._httpServer!.address,
        _instance._httpServer!.port,
        _instance._httpServer!.autoCompress,
        _instance._httpServer!.defaultResponseHeaders,
        _instance._httpServer!.idleTimeout,
        _instance._httpServer!.serverHeader);
    if (_instance._listeningToServer) return _serverInfo;
    _instance._httpServer!.listen(((event) async {
      await _parseRequest(event).timeout(
          _instance.requestTimeOut != null
              ? _instance.requestTimeOut!
              : Duration(seconds: 120), onTimeout: () {
        throw TimeoutException(
            'the requests takes more than the specified timeout');
      });
    }));

    _instance._listeningToServer = true;

    return _serverInfo;
  }

  Future<bool> _parseRequest(HttpRequest httpRequest) async {
    if (httpRequest.headers.value('Upgrade') == null) {
      return handleHttpRequest(httpRequest);
    } else if (httpRequest.headers.value("Upgrade") != null &&
        httpRequest.headers.value("Upgrade") == "websocket") {
      if (WebSocketTransformer.isUpgradeRequest(httpRequest)) {
        WebSocketTransformer.upgrade(httpRequest).then((WebSocket websocket) {
          UpgradedWebSocket _upgradedWebSocket = UpgradedWebSocket(
              websocket, httpRequest.headers, httpRequest.uri);
          _webSocketStream.sink.add(_upgradedWebSocket);
          _webSocketStreamBroadcast.sink.add(_upgradedWebSocket);
          return true;
        });
      }
    }
    return true;
  }

  final List<RestControllerRoutesMapping> _registredRoutes = [];

  void _registerRoutes() {
    if (application.controllers.isNotEmpty) {
      for (Type type in application.controllers) {
        ClassMirror cm = reflectClass(type);

        for (var md in cm.metadata) {
          InstanceMirror metadata = md;

          if (metadata.reflectee is RestController) {
            String controllerPath = metadata.getField(#path).reflectee;
            InstanceMirror controllerInstanceMirroir =
                cm.newInstance(Symbol(''), []);
            ControllerInstance controllerInstance =
                ControllerInstance(controllerPath, controllerInstanceMirroir);
            cm.declarations.forEach((key, value) {
              if (value is MethodMirror) {
                for (var element in value.metadata) {
                  if (element.reflectee is Route) {
                    InstanceMirror instanceMirror = reflect(element.reflectee);
                    int index = _registredRoutes.indexWhere((element) =>
                        element.controllerInstance.instanceMirror ==
                        controllerInstanceMirroir);
                    Map<Symbol, ARoute> map = {
                      value.simpleName: Route(
                          instanceMirror.getField(#path).reflectee,
                          instanceMirror.getField(#method).reflectee)
                    };
                    if (index != -1) {
                      Map<Symbol, ARoute> temp = _registredRoutes[index].routes;
                      map.addAll(temp);

                      _registredRoutes[index] =
                          RestControllerRoutesMapping(controllerInstance, map);
                    } else {
                      _registredRoutes.add(
                          RestControllerRoutesMapping(controllerInstance, map));
                    }
                  }
                  if (element.reflectee is AuthenticatedRoute) {
                    InstanceMirror instanceMirror = reflect(element.reflectee);
                    Map<Symbol, ARoute> map = {
                      value.simpleName: AuthenticatedRoute(
                          instanceMirror.getField(#path).reflectee,
                          instanceMirror.getField(#method).reflectee,
                          instanceMirror.getField(#middlwareHandler).reflectee)
                    };

                    int index = _registredRoutes.indexWhere((element) =>
                        element.controllerInstance.instanceMirror ==
                        controllerInstanceMirroir);
                    if (index != -1) {
                      Map<Symbol, ARoute> temp = _registredRoutes[index].routes;
                      map.addAll(temp);

                      _registredRoutes[index] =
                          RestControllerRoutesMapping(controllerInstance, map);
                    } else {
                      _registredRoutes.add(
                          RestControllerRoutesMapping(controllerInstance, map));
                    }
                  }
                  if (element.reflectee is AuthorizatedRoute) {
                    InstanceMirror instanceMirror = reflect(element.reflectee);
                    Map<Symbol, ARoute> map = {
                      value.simpleName: AuthorizatedRoute(
                          instanceMirror.getField(#path).reflectee,
                          instanceMirror.getField(#method).reflectee,
                          instanceMirror.getField(#middlwareHandler).reflectee,
                          instanceMirror.getField(#roles).reflectee,
                          instanceMirror.getField(#userProvider).reflectee)
                    };
                    int index = _registredRoutes.indexWhere((element) =>
                        element.controllerInstance.instanceMirror ==
                        controllerInstanceMirroir);
                    if (index != -1) {
                      Map<Symbol, ARoute> temp = _registredRoutes[index].routes;
                      map.addAll(temp);

                      _registredRoutes[index] =
                          RestControllerRoutesMapping(controllerInstance, map);
                    } else {
                      _registredRoutes.add(
                          RestControllerRoutesMapping(controllerInstance, map));
                    }
                  }
                }
              }
            });
          }
        }
      }
    } else {
      MirrorSystem mirrorSystem = currentMirrorSystem();

      mirrorSystem.libraries.forEach((lk, l) {
        l.declarations.forEach((dk, d) {
          if (d is ClassMirror) {
            ClassMirror cm = d;
            for (var md in cm.metadata) {
              InstanceMirror metadata = md;
              if (metadata.reflectee is RestController) {
                String controllerPath = metadata.getField(#path).reflectee;
                InstanceMirror controllerInstanceMirroir =
                    cm.newInstance(Symbol(''), []);
                ControllerInstance controllerInstance = ControllerInstance(
                    controllerPath, controllerInstanceMirroir);

                cm.declarations.forEach((key, value) {
                  if (value is MethodMirror) {
                    for (var element in value.metadata) {
                      if (element.reflectee is Route) {
                        InstanceMirror instanceMirror =
                            reflect(element.reflectee);
                        int index = _registredRoutes.indexWhere((element) =>
                            element.controllerInstance.instanceMirror ==
                            controllerInstanceMirroir);
                        Map<Symbol, ARoute> map = {
                          value.simpleName: Route(
                              instanceMirror.getField(#path).reflectee,
                              instanceMirror.getField(#method).reflectee)
                        };
                        if (index != -1) {
                          Map<Symbol, ARoute> temp =
                              _registredRoutes[index].routes;
                          map.addAll(temp);

                          _registredRoutes[index] = RestControllerRoutesMapping(
                              controllerInstance, map);
                        } else {
                          _registredRoutes.add(RestControllerRoutesMapping(
                              controllerInstance, map));
                        }
                      }
                      if (element.reflectee is AuthenticatedRoute) {
                        InstanceMirror instanceMirror =
                            reflect(element.reflectee);
                        Map<Symbol, ARoute> map = {
                          value.simpleName: AuthenticatedRoute(
                              instanceMirror.getField(#path).reflectee,
                              instanceMirror.getField(#method).reflectee,
                              instanceMirror
                                  .getField(#middlwareHandler)
                                  .reflectee)
                        };

                        int index = _registredRoutes.indexWhere((element) =>
                            element.controllerInstance.instanceMirror ==
                            controllerInstanceMirroir);
                        if (index != -1) {
                          Map<Symbol, ARoute> temp =
                              _registredRoutes[index].routes;
                          map.addAll(temp);

                          _registredRoutes[index] = RestControllerRoutesMapping(
                              controllerInstance, map);
                        } else {
                          _registredRoutes.add(RestControllerRoutesMapping(
                              controllerInstance, map));
                        }
                      }
                      if (element.reflectee is AuthorizatedRoute) {
                        InstanceMirror instanceMirror =
                            reflect(element.reflectee);
                        Map<Symbol, ARoute> map = {
                          value.simpleName: AuthorizatedRoute(
                              instanceMirror.getField(#path).reflectee,
                              instanceMirror.getField(#method).reflectee,
                              instanceMirror
                                  .getField(#middlwareHandler)
                                  .reflectee,
                              instanceMirror.getField(#roles).reflectee,
                              instanceMirror.getField(#userProvider).reflectee)
                        };
                        int index = _registredRoutes.indexWhere((element) =>
                            element.controllerInstance.instanceMirror ==
                            controllerInstanceMirroir);
                        if (index != -1) {
                          Map<Symbol, ARoute> temp =
                              _registredRoutes[index].routes;
                          map.addAll(temp);

                          _registredRoutes[index] = RestControllerRoutesMapping(
                              controllerInstance, map);
                        } else {
                          _registredRoutes.add(RestControllerRoutesMapping(
                              controllerInstance, map));
                        }
                      }
                    }
                  }
                });
              }
            }
          }
        });
      });
    }
  }

  Future<bool> handleHttpRequest(HttpRequest httpRequest) async {
    final String path = httpRequest.uri.path;

    final String method = httpRequest.method;

    List<RestControllerRoutesMapping> matchedPaths =
        RoutesHandler.getMatchedRoute1s(_registredRoutes, path);

    if (matchedPaths.isNotEmpty) {
      for (RestControllerRoutesMapping restControllerRoutesMapping
          in matchedPaths) {
        for (var element in restControllerRoutesMapping.routes.entries) {
          ARoute aRoute = element.value;
          final String fullPath =
              restControllerRoutesMapping.controllerInstance.controllerPath +
                  aRoute.path;

          if (aRoute.method.requestMethod == method) {
            Map<String, dynamic>? pathParams = RoutesHandler.pathMatcher(
                routePath: fullPath, matchesPath: path);
            Request request =
                await BodyParser.parseBody(httpRequest, pathParams);
            Response response = Response(httpRequest.response, application);
            if (aRoute is Route) {
              restControllerRoutesMapping.controllerInstance.instanceMirror
                  .invoke(element.key, [request, response]);
            } else if (aRoute is AuthenticatedRoute) {
              final List<MiddlwareAnnotationEntity> middlwares = [];
              InstanceMirror instanceMirror = reflect(aRoute.middlwareHandler);
              ClassMirror classMirror = instanceMirror.type;
              classMirror.declarations.forEach((key, value) {
                if (value is MethodMirror && value.isRegularMethod) {
                  for (var element in value.metadata) {
                    if (element.reflectee is Middleware) {
                      InstanceMirror instanceMirror =
                          reflect(element.reflectee);
                      middlwares.add(MiddlwareAnnotationEntity(value.simpleName,
                          instanceMirror.getField(#priority).reflectee));
                    }
                  }
                }
              });
              middlwares.sort(((a, b) => b.priority - a.priority));
              for (MiddlwareAnnotationEntity middlwareAnnotationEntity
                  in middlwares) {
                final MiddleWareResponse result = await instanceMirror.invoke(
                    middlwareAnnotationEntity.methodName,
                    [request, response]).reflectee;

                if (result.value == MiddleWareResponseEnum.stop) {
                  return true;
                }
              }
              restControllerRoutesMapping.controllerInstance.instanceMirror
                  .invoke(element.key, [request, response]);
            } else if (aRoute is AuthorizatedRoute) {
              final List<MiddlwareAnnotationEntity> middlwares = [];
              InstanceMirror authenticationProviderInstance =
                  reflect(aRoute.userProvider);
              ClassMirror authClassMirroir =
                  authenticationProviderInstance.type;
              List<Symbol> authFuncts = [];
              for (var value in authClassMirroir.declarations.values) {
                if (value is MethodMirror && value.isRegularMethod) {
                  for (var element in value.metadata) {
                    if (element.reflectee is AuthorizationRequired) {
                      authFuncts.add(value.simpleName);
                    }
                  }
                }
              }
              if (authFuncts.isEmpty) {
                throw Exception(
                    'your need to implenent a function with @AuthorizationREquired inside the class');
              } else if (authFuncts.length > 1) {
                throw Exception(
                    'your need to implenent only one function with @AuthorizationREquired inside the class');
              }
              final UserDetails? userDetails =
                  await authenticationProviderInstance.invoke(authFuncts.first,
                      [request, response, aRoute.roles]).reflectee;
              if (userDetails == null) {
                return true;
              }
              request = request.copyWith(userDetails: userDetails);
              InstanceMirror instanceMirror = reflect(aRoute.middlwareHandler);
              ClassMirror classMirror = instanceMirror.type;
              classMirror.declarations.forEach((key, value) {
                if (value is MethodMirror && value.isRegularMethod) {
                  for (var element in value.metadata) {
                    if (element.reflectee is Middleware) {
                      InstanceMirror instanceMirror =
                          reflect(element.reflectee);

                      middlwares.add(MiddlwareAnnotationEntity(value.simpleName,
                          instanceMirror.getField(#priority).reflectee));
                    }
                  }
                }
              });
              middlwares.sort(((a, b) => b.priority - a.priority));
              for (MiddlwareAnnotationEntity middlwareAnnotationEntity
                  in middlwares) {
                final MiddleWareResponse result = await instanceMirror.invoke(
                    middlwareAnnotationEntity.methodName,
                    [request, response]).reflectee;

                if (result.value == MiddleWareResponseEnum.stop) {
                  return true;
                }
              }
              restControllerRoutesMapping.controllerInstance.instanceMirror
                  .invoke(element.key, [request, response]);
            }
          } else {
            methodNotAllowedException(httpRequest.response, path, method);
            return true;
          }
        }
      }
    } else {
      routeNotFoundException(httpRequest.response, path, method);
      return true;
    }
    return true;
  }
}
