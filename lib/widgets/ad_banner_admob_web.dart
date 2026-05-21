import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

final _registeredViewTypes = <String>{};
bool _scriptInjected = false;

@JS('eval')
external JSAny? _jsEval(String code);

Widget buildAdmobView(String publisherId, String adUnitId) =>
    _AdmobView(publisherId: publisherId, adUnitId: adUnitId);

class _AdmobView extends StatefulWidget {
  final String publisherId;
  final String adUnitId;

  const _AdmobView({required this.publisherId, required this.adUnitId});

  @override
  State<_AdmobView> createState() => _AdmobViewState();
}

class _AdmobViewState extends State<_AdmobView> {
  late final String _viewType;

  @override
  void initState() {
    super.initState();
    _viewType = 'admob-banner-${widget.adUnitId}';
    _ensureScriptInjected(widget.publisherId);
    _ensureViewRegistered(_viewType, widget.publisherId, widget.adUnitId);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _jsEval('(adsbygoogle=window.adsbygoogle||[]).push({})'),
    );
  }

  static void _ensureScriptInjected(String publisherId) {
    if (_scriptInjected) return;
    _scriptInjected = true;
    final script =
        web.document.createElement('script') as web.HTMLScriptElement;
    script.async = true;
    script.src =
        'https://pagead2.googlesyndication.com/pagead/js/adsbygoogle.js?client=$publisherId';
    script.crossOrigin = 'anonymous';
    web.document.head!.appendChild(script);
  }

  static void _ensureViewRegistered(
    String viewType,
    String publisherId,
    String adUnitId,
  ) {
    if (_registeredViewTypes.contains(viewType)) return;
    _registeredViewTypes.add(viewType);

    ui_web.platformViewRegistry.registerViewFactory(viewType, (int viewId) {
      final container =
          web.document.createElement('div') as web.HTMLDivElement;
      container.style.width = '100%';
      container.style.height = '100%';

      final ins = web.document.createElement('ins') as web.HTMLElement;
      ins.className = 'adsbygoogle';
      ins.style.display = 'block';
      ins.style.width = '100%';
      ins.style.height = '100%';
      ins.setAttribute('data-ad-client', publisherId);
      ins.setAttribute('data-ad-slot', adUnitId);
      ins.setAttribute('data-ad-format', 'auto');
      ins.setAttribute('data-full-width-responsive', 'true');
      container.appendChild(ins);

      return container;
    });
  }

  @override
  Widget build(BuildContext context) {
    return HtmlElementView(viewType: _viewType);
  }
}
