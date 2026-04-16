# Verein Screen Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a Verein settings screen where club admins manage their own club and super-admins manage all clubs centrally (name, logo, active screens).

**Architecture:** Backend gains three new Lambda endpoints (list/create/update customers) plus `isSuperAdmin` on members. The Flutter screen reads club settings on load, shows a dropdown for super-admins only, and persists changes via the update endpoint. The home screen filters its tile grid using the `active_screens` field from the customer record.

**Tech Stack:** Python 3.10 (Lambda), boto3 (DynamoDB), Flutter/Dart, file_picker (image upload), AWS API Gateway HTTP API, Terraform

---

### Task 1: Add `isSuperAdmin` to members API

**Files:**
- Modify: `aws_backend/lambda/api_members.py:81-87, 116-140`
- Modify: `aws_backend/lambda/tests/test_api_members.py`

- [ ] **Step 1: Write failing tests for `isSuperAdmin`**

Add these two test cases to `aws_backend/lambda/tests/test_api_members.py`, inside a new `TestSuperAdmin` class at the bottom of the file:

```python
class TestSuperAdmin(unittest.TestCase):
    def setUp(self):
        self.mock_table = MagicMock()
        api_members.members_table = self.mock_table

        self.super_admin = {
            'memberId': 'super1',
            'name': 'Super Admin',
            'isAdmin': True,
            'isSpiess': False,
            'isSuperAdmin': True,
            'token': '',
        }

        def get_item_side_effect(Key):
            data = {'super1': self.super_admin}
            item = data.get(Key.get('memberId'))
            return {'Item': item} if item else {}

        self.mock_table.get_item.side_effect = get_item_side_effect

    def test_get_member_includes_is_super_admin(self):
        event = {
            'requestContext': {'http': {'method': 'GET', 'path': '/members/super1'}},
            'headers': {'memberid': 'super1'},
            'pathParameters': {'memberId': 'super1'},
        }
        response = api_members.handle_members(event, {})
        self.assertEqual(response['statusCode'], 200)
        body = json.loads(response['body'])
        self.assertIn('isSuperAdmin', body)
        self.assertTrue(body['isSuperAdmin'])

    def test_add_member_stores_is_super_admin(self):
        self.mock_table.put_item.return_value = {}
        event = {
            'requestContext': {'http': {'method': 'POST', 'path': '/members'}},
            'headers': {'memberid': 'super1'},
            'pathParameters': {},
            'body': json.dumps({
                'memberId': 'newsuper',
                'name': 'New Super',
                'isSuperAdmin': True,
            }),
        }
        response = api_members.handle_members(event, {})
        self.assertEqual(response['statusCode'], 200)
        body = json.loads(response['body'])
        self.assertTrue(body['isSuperAdmin'])
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
cd aws_backend/lambda && python -m pytest tests/test_api_members.py::TestSuperAdmin -v
```

Expected: FAIL — `isSuperAdmin` not in body

- [ ] **Step 3: Add `isSuperAdmin` to `get_member` reduced fields**

In `aws_backend/lambda/api_members.py`, replace lines 81–87 (the `else` branch of `get_member`):

```python
    else:
        result = {
            'memberId': item['memberId'],
            'name': item['name'],
            'isAdmin': item.get('isAdmin', False),
            'isSpiess': item.get('isSpiess', False),
            'isSuperAdmin': item.get('isSuperAdmin', False),
            'token': item.get('token', ''),
        }
```

- [ ] **Step 4: Add `isSuperAdmin` to `add_member`**

In `aws_backend/lambda/api_members.py`, replace the `add_member` function body (lines 112–147) with:

```python
def add_member(body):
    data = json.loads(body)
    data_member_id = data['memberId']
    data_name = data['name']
    data_is_admin = data.get('isAdmin', False)
    data_is_spiess = data.get('isSpiess', False)
    data_is_super_admin = data.get('isSuperAdmin', False)
    data_token = data.get('token', '')
    data_street = data.get('street', '')
    data_house_number = data.get('houseNumber', '')
    data_postal_code = data.get('postalCode', '')
    data_city = data.get('city', '')
    data_phone1 = data.get('phone1', '')
    data_phone2 = data.get('phone2', '')
    data_is_active = data.get('isActive', True)

    item = {
        'memberId': data_member_id,
        'name': data_name,
        'isAdmin': data_is_admin,
        'isSpiess': data_is_spiess,
        'isSuperAdmin': data_is_super_admin,
        'isActive': data_is_active,
        'token': data_token,
        'street': data_street,
        'houseNumber': data_house_number,
        'postalCode': data_postal_code,
        'city': data_city,
        'phone1': data_phone1,
        'phone2': data_phone2,
    }

    members_table.put_item(Item=item)

    return {
        'statusCode': 200,
        'body': json.dumps(item)
    }
```

- [ ] **Step 5: Run tests to confirm they pass**

```bash
cd aws_backend/lambda && python -m pytest tests/test_api_members.py::TestSuperAdmin -v
```

Expected: PASS

- [ ] **Step 6: Run full test suite to check for regressions**

```bash
cd aws_backend/lambda && python -m pytest tests/ -v
```

Expected: all tests pass

- [ ] **Step 7: Commit**

```bash
git add aws_backend/lambda/api_members.py aws_backend/lambda/tests/test_api_members.py
git commit -m "feat: add isSuperAdmin field to members API"
```

---

### Task 2: Add customer list/create/update endpoints

**Files:**
- Modify: `aws_backend/lambda/api_customers.py`
- Create: `aws_backend/lambda/tests/test_api_customers.py`

- [ ] **Step 1: Create the test file**

Create `aws_backend/lambda/tests/test_api_customers.py`:

```python
import json
import os
import sys
import unittest
from unittest.mock import MagicMock

sys.modules.setdefault('boto3', MagicMock())

sys.path.insert(0, '.')
import api_customers


def _event(method, path, body=None, customer_id=None):
    event = {
        'requestContext': {'http': {'method': method, 'path': path}},
        'headers': {},
        'pathParameters': {},
    }
    if customer_id:
        event['pathParameters']['customerId'] = customer_id
    if body is not None:
        event['body'] = json.dumps(body)
    return event


class TestListCustomers(unittest.TestCase):
    def setUp(self):
        self.mock_table = MagicMock()
        api_customers.table = MagicMock(return_value=self.mock_table)

    def test_returns_all_clubs(self):
        clubs = [
            {'application_id': 'club1', 'application_name': 'Club 1'},
            {'application_id': 'club2', 'application_name': 'Club 2'},
        ]
        self.mock_table.scan.return_value = {'Items': clubs}
        response = api_customers.list_customers()
        self.assertEqual(response['statusCode'], 200)
        items = json.loads(response['body'])
        self.assertEqual(len(items), 2)
        self.assertEqual(items[0]['application_id'], 'club1')

    def test_handles_pagination(self):
        self.mock_table.scan.side_effect = [
            {'Items': [{'application_id': 'c1'}], 'LastEvaluatedKey': {'application_id': 'c1'}},
            {'Items': [{'application_id': 'c2'}]},
        ]
        response = api_customers.list_customers()
        items = json.loads(response['body'])
        self.assertEqual(len(items), 2)


class TestUpdateCustomer(unittest.TestCase):
    def setUp(self):
        self.mock_table = MagicMock()
        api_customers.table = MagicMock(return_value=self.mock_table)

    def test_update_customer(self):
        event = _event(
            'PUT', '/customers/club1',
            body={'application_name': 'New Name', 'active_screens': ['termine', 'strafen']},
            customer_id='club1',
        )
        response = api_customers.update_customer(event)
        self.assertEqual(response['statusCode'], 200)
        self.mock_table.update_item.assert_called_once()
        call_kwargs = self.mock_table.update_item.call_args[1]
        self.assertEqual(call_kwargs['Key'], {'application_id': 'club1'})

    def test_update_customer_with_logo(self):
        event = _event(
            'PUT', '/customers/club1',
            body={
                'application_name': 'New Name',
                'application_logo': 'abc123',
                'active_screens': ['termine'],
            },
            customer_id='club1',
        )
        response = api_customers.update_customer(event)
        self.assertEqual(response['statusCode'], 200)
        call_kwargs = self.mock_table.update_item.call_args[1]
        self.assertIn(':logo', call_kwargs['ExpressionAttributeValues'])


class TestCreateCustomer(unittest.TestCase):
    def setUp(self):
        self.mock_table = MagicMock()
        api_customers.table = MagicMock(return_value=self.mock_table)

    def test_create_customer_success(self):
        self.mock_table.get_item.return_value = {}
        event = _event(
            'POST', '/customers',
            body={'application_id': 'newclub', 'application_name': 'New Club'},
        )
        response = api_customers.create_customer(event)
        self.assertEqual(response['statusCode'], 200)
        self.mock_table.put_item.assert_called_once()
        item = json.loads(response['body'])
        self.assertEqual(item['application_id'], 'newclub')

    def test_create_customer_defaults_active_screens(self):
        self.mock_table.get_item.return_value = {}
        event = _event(
            'POST', '/customers',
            body={'application_id': 'newclub', 'application_name': 'New Club'},
        )
        response = api_customers.create_customer(event)
        item = json.loads(response['body'])
        self.assertEqual(len(item['active_screens']), 6)

    def test_create_customer_conflict(self):
        self.mock_table.get_item.return_value = {'Item': {'application_id': 'existing'}}
        event = _event(
            'POST', '/customers',
            body={'application_id': 'existing', 'application_name': 'Existing'},
        )
        response = api_customers.create_customer(event)
        self.assertEqual(response['statusCode'], 409)
        self.mock_table.put_item.assert_not_called()

    def test_create_customer_uses_api_base_url_default(self):
        self.mock_table.get_item.return_value = {}
        os.environ['API_BASE_URL'] = 'https://api.example.com'
        api_customers.API_BASE_URL = 'https://api.example.com'
        event = _event(
            'POST', '/customers',
            body={'application_id': 'newclub', 'application_name': 'New Club'},
        )
        response = api_customers.create_customer(event)
        item = json.loads(response['body'])
        self.assertEqual(item['api_url'], 'https://api.example.com')
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
cd aws_backend/lambda && python -m pytest tests/test_api_customers.py -v
```

Expected: FAIL — `list_customers`, `update_customer`, `create_customer` not defined

- [ ] **Step 3: Implement the three new functions in `api_customers.py`**

Add the following to `aws_backend/lambda/api_customers.py`, after the existing imports and `table()` function:

```python
import os

ALL_SCREEN_KEYS = ['termine', 'marschbefehl', 'strafen', 'dokumente', 'galerie', 'schere_stein_papier']
API_BASE_URL = os.environ.get('API_BASE_URL', '')


def list_customers():
    t = table()
    items = []
    response = t.scan()
    items.extend(response.get('Items', []))
    while 'LastEvaluatedKey' in response:
        response = t.scan(ExclusiveStartKey=response['LastEvaluatedKey'])
        items.extend(response.get('Items', []))

    return {
        'statusCode': 200,
        'body': json.dumps(items)
    }


def update_customer(event):
    customer_id = event['pathParameters']['customerId']
    body = json.loads(event['body'])

    update_expr = 'SET application_name = :name, active_screens = :screens'
    expr_values = {
        ':name': body['application_name'],
        ':screens': body.get('active_screens', ALL_SCREEN_KEYS),
    }
    logo = body.get('application_logo', '')
    if logo:
        update_expr += ', application_logo = :logo'
        expr_values[':logo'] = logo

    table().update_item(
        Key={'application_id': customer_id},
        UpdateExpression=update_expr,
        ExpressionAttributeValues=expr_values,
    )

    return {
        'statusCode': 200,
        'body': json.dumps({'message': 'Verein aktualisiert'})
    }


def create_customer(event):
    body = json.loads(event['body'])
    application_id = body['application_id']
    application_name = body['application_name']
    api_url = body.get('api_url') or API_BASE_URL
    application_logo = body.get('application_logo', '')
    active_screens = body.get('active_screens', ALL_SCREEN_KEYS)

    t = table()
    response = t.get_item(Key={'application_id': application_id})
    if response.get('Item'):
        return {
            'statusCode': 409,
            'body': json.dumps({'error': 'Verein existiert bereits'})
        }

    item = {
        'application_id': application_id,
        'application_name': application_name,
        'api_url': api_url,
        'application_logo': application_logo,
        'active_screens': active_screens,
    }
    t.put_item(Item=item)

    return {
        'statusCode': 200,
        'body': json.dumps(item)
    }
```

Note: `api_customers.py` already imports `json` and `os` at the top — do not add duplicate imports. Only add `ALL_SCREEN_KEYS`, `API_BASE_URL`, and the three functions.

- [ ] **Step 4: Run tests to confirm they pass**

```bash
cd aws_backend/lambda && python -m pytest tests/test_api_customers.py -v
```

Expected: all 7 tests PASS

- [ ] **Step 5: Run full test suite**

```bash
cd aws_backend/lambda && python -m pytest tests/ -v
```

Expected: all tests pass

- [ ] **Step 6: Commit**

```bash
git add aws_backend/lambda/api_customers.py aws_backend/lambda/tests/test_api_customers.py
git commit -m "feat: add list, create, update endpoints to customers API"
```

---

### Task 3: Route new customer endpoints in lambda_handler

**Files:**
- Modify: `aws_backend/lambda/lambda_handler.py:50-87`

- [ ] **Step 1: Add the three new routes**

In `aws_backend/lambda/lambda_handler.py`, find the routing block inside `lambda_handler`. Replace the existing customers block:

```python
        elif method == 'GET' and path.startswith('/customers/'):
            import api_customers
            return {**headers, **api_customers.get_customer_by_id(event, context)}
```

With:

```python
        elif method == 'GET' and path == '/customers':
            import api_customers
            return {**headers, **api_customers.list_customers()}
        elif method == 'POST' and path == '/customers':
            import api_customers
            return {**headers, **api_customers.create_customer(event)}
        elif method == 'PUT' and path.startswith('/customers/'):
            import api_customers
            return {**headers, **api_customers.update_customer(event)}
        elif method == 'GET' and path.startswith('/customers/'):
            import api_customers
            return {**headers, **api_customers.get_customer_by_id(event, context)}
```

The order matters: `GET /customers` (exact) must come before `GET /customers/{id}` (prefix match).

- [ ] **Step 2: Commit**

```bash
git add aws_backend/lambda/lambda_handler.py
git commit -m "feat: route GET/POST /customers and PUT /customers/{id} in lambda handler"
```

---

### Task 4: Terraform — add API Gateway routes and env vars

**Files:**
- Modify: `aws_backend/api_customers.tf`
- Modify: `aws_backend/lambda_backend.tf`

- [ ] **Step 1: Add three new API Gateway routes to `api_customers.tf`**

Append to the end of `aws_backend/api_customers.tf`:

```hcl
resource "aws_apigatewayv2_route" "customer_list" {
    api_id             = aws_apigatewayv2_api.http_api.id
    route_key          = "GET /customers"
    target             = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
    authorization_type = "CUSTOM"
    authorizer_id      = aws_apigatewayv2_authorizer.lambda_authorizer.id
}

resource "aws_apigatewayv2_route" "customer_post" {
    api_id             = aws_apigatewayv2_api.http_api.id
    route_key          = "POST /customers"
    target             = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
    authorization_type = "CUSTOM"
    authorizer_id      = aws_apigatewayv2_authorizer.lambda_authorizer.id
}

resource "aws_apigatewayv2_route" "customer_put" {
    api_id             = aws_apigatewayv2_api.http_api.id
    route_key          = "PUT /customers/{customerId}"
    target             = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
    authorization_type = "CUSTOM"
    authorizer_id      = aws_apigatewayv2_authorizer.lambda_authorizer.id
}
```

- [ ] **Step 2: Add `PUT` to CORS and `API_BASE_URL` env var in `lambda_backend.tf`**

In `aws_backend/lambda_backend.tf`, make two changes:

**Change 1** — add `API_BASE_URL` to the Lambda environment variables block (lines 9–17):

```hcl
    environment {
        variables = {
            ERROR_TABLE_NAME         = aws_dynamodb_table.error_table.name,
            CUSTOMERS_TABLE_NAME     = aws_dynamodb_table.customer_config_table.name,
            FINES_TABLE_NAME         = aws_dynamodb_table.fines_table.name,
            MEMBERS_TABLE_NAME       = aws_dynamodb_table.members_table.name,
            MARSCHBEFEHL_TABLE_NAME  = aws_dynamodb_table.marschbefehl_table.name,
            S3_BUCKET_NAME           = aws_s3_bucket.s3_bucket.bucket,
            API_BASE_URL             = aws_apigatewayv2_api.http_api.api_endpoint,
        }
    }
```

**Change 2** — add `"PUT"` to the CORS allow_methods list (line 52):

```hcl
        allow_methods     = ["GET", "POST", "DELETE", "OPTIONS", "PUT"]
```

- [ ] **Step 3: Validate Terraform config**

```bash
cd aws_backend && terraform validate
```

Expected: `Success! The configuration is valid.`

- [ ] **Step 4: Commit**

```bash
git add aws_backend/api_customers.tf aws_backend/lambda_backend.tf
git commit -m "feat: add API Gateway routes for customers list/create/update, add PUT to CORS"
```

---

### Task 5: Add `isSuperAdmin` to Flutter Member model

**Files:**
- Modify: `lib/config_loader.dart`

- [ ] **Step 1: Add `isSuperAdmin` field, getter, setter, and encode/decode**

In `lib/config_loader.dart`, make four targeted edits:

**Edit 1** — add field after `bool _isAdmin = false;` (around line 109):

```dart
  bool _isSuperAdmin = false;
```

**Edit 2** — add getter after `bool get isAdmin => _isAdmin;` (around line 131):

```dart
  bool get isSuperAdmin => _isSuperAdmin;
```

**Edit 3** — add setter after `set isAdmin(bool value) => _isAdmin = value;` (around line 147):

```dart
  set isSuperAdmin(bool value) => _isSuperAdmin = value;
```

**Edit 4** — add to `updateMember` after `_isAdmin = member?['isAdmin'] ?? false;` (around line 227):

```dart
    _isSuperAdmin = member?['isSuperAdmin'] ?? false;
```

**Edit 5** — add to `encodeMember` after `'isAdmin': _isAdmin,` (around line 247):

```dart
      'isSuperAdmin': _isSuperAdmin,
```

- [ ] **Step 2: Verify the app still compiles**

```bash
cd /path/to/project && flutter analyze lib/config_loader.dart
```

Expected: no errors

- [ ] **Step 3: Commit**

```bash
git add lib/config_loader.dart
git commit -m "feat: add isSuperAdmin field to Member model"
```

---

### Task 6: Extend Flutter CustomersApi

**Files:**
- Modify: `lib/api/customers_api.dart`

- [ ] **Step 1: Add `listCustomers`, `updateCustomer`, `createCustomer`**

Replace the entire content of `lib/api/customers_api.dart` with:

```dart
// lib/api/customers_api.dart
import 'dart:convert';
import 'package:http/http.dart' as http;

import '../config_loader.dart';
import 'headers.dart';

class CustomersApi {
  final AppConfig config;
  final http.Client _client;

  CustomersApi(this.config, {http.Client? client})
      : _client = client ?? http.Client();

  Future<Map<String, dynamic>> getCustomer(String customerId) async {
    final response = await _client.get(
      Uri.parse('${config.apiBaseUrl}/customers/$customerId'),
      headers: headers(config),
    );
    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Fehler beim Laden des Vereins: ${response.statusCode}');
    }
  }

  Future<List<Map<String, dynamic>>> listCustomers() async {
    final response = await _client.get(
      Uri.parse('${config.apiBaseUrl}/customers'),
      headers: headers(config),
    );
    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);
      return data.cast<Map<String, dynamic>>();
    } else {
      throw Exception('Fehler beim Laden der Vereine: ${response.statusCode}');
    }
  }

  Future<void> updateCustomer(String id, Map<String, dynamic> data) async {
    final response = await _client.put(
      Uri.parse('${config.apiBaseUrl}/customers/$id'),
      headers: headers(config),
      body: json.encode(data),
    );
    if (response.statusCode != 200) {
      throw Exception('Fehler beim Speichern: ${response.statusCode}');
    }
  }

  Future<Map<String, dynamic>> createCustomer(Map<String, dynamic> data) async {
    final response = await _client.post(
      Uri.parse('${config.apiBaseUrl}/customers'),
      headers: headers(config),
      body: json.encode(data),
    );
    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Fehler beim Erstellen: ${response.statusCode}');
    }
  }
}
```

- [ ] **Step 2: Verify**

```bash
flutter analyze lib/api/customers_api.dart
```

Expected: no errors

- [ ] **Step 3: Commit**

```bash
git add lib/api/customers_api.dart
git commit -m "feat: add listCustomers, updateCustomer, createCustomer to CustomersApi"
```

---

### Task 7: Build VereinScreen

**Files:**
- Create: `lib/screens/verein_screen.dart`

- [ ] **Step 1: Create the screen**

Create `lib/screens/verein_screen.dart`:

```dart
// lib/screens/verein_screen.dart
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../api/customers_api.dart';
import '../config_loader.dart';
import 'default_screen.dart';

const _allScreens = [
  {'key': 'termine', 'label': '📅 Termine'},
  {'key': 'marschbefehl', 'label': '📢 Marschbefehl'},
  {'key': 'strafen', 'label': '💰 Strafen'},
  {'key': 'dokumente', 'label': '📄 Dokumente'},
  {'key': 'galerie', 'label': '📸 Fotogalerie'},
  {'key': 'schere_stein_papier', 'label': '✂️ Schere Stein Papier'},
];

class VereinScreen extends DefaultScreen {
  const VereinScreen({super.key, required super.config})
      : super(title: 'Verein');

  @override
  DefaultScreenState<VereinScreen> createState() => _VereinScreenState();
}

class _VereinScreenState extends DefaultScreenState<VereinScreen> {
  late final CustomersApi _api;

  List<Map<String, dynamic>> _allClubs = [];
  Map<String, dynamic>? _selectedClub;

  final _nameController = TextEditingController();
  String _logoBase64 = '';
  List<String> _activeScreens =
      _allScreens.map((s) => s['key']!).toList();

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _api = CustomersApi(widget.config);
    _loadData();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => isLoading = true);
    try {
      if (widget.config.member.isSuperAdmin) {
        final clubs = await _api.listCustomers();
        if (!mounted) return;
        setState(() {
          _allClubs = clubs;
          isLoading = false;
        });
        if (clubs.isNotEmpty) _applyClub(clubs.first);
      } else {
        final club = await _api.getCustomer(widget.config.applicationId);
        if (!mounted) return;
        setState(() => isLoading = false);
        _applyClub(club);
      }
    } catch (e) {
      if (mounted) setState(() => isLoading = false);
      showError('Fehler beim Laden: $e');
    }
  }

  void _applyClub(Map<String, dynamic> club) {
    setState(() {
      _selectedClub = club;
      _nameController.text = club['application_name'] ?? '';
      _logoBase64 = club['application_logo'] ?? '';
      final screens = club['active_screens'];
      _activeScreens = screens != null
          ? List<String>.from(screens)
          : _allScreens.map((s) => s['key']!).toList();
    });
  }

  Future<void> _pickLogo() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final bytes = result.files.first.bytes;
    if (bytes == null) return;
    setState(() => _logoBase64 = base64Encode(bytes));
  }

  Future<void> _save() async {
    final clubId =
        _selectedClub?['application_id'] ?? widget.config.applicationId;
    setState(() => _saving = true);
    try {
      await _api.updateCustomer(clubId, {
        'application_name': _nameController.text.trim(),
        'application_logo': _logoBase64,
        'active_screens': _activeScreens,
      });
      showInfo('Gespeichert');
    } catch (e) {
      showError('Fehler beim Speichern: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showCreateDialog() {
    final idCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    final urlCtrl = TextEditingController();
    String dialogLogo = '';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Neuen Verein erstellen'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: idCtrl,
                  decoration:
                      const InputDecoration(labelText: 'Application ID *'),
                ),
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Name *'),
                ),
                TextField(
                  controller: urlCtrl,
                  decoration:
                      const InputDecoration(labelText: 'API URL (optional)'),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    TextButton.icon(
                      icon: const Icon(Icons.image),
                      label: const Text('Logo wählen (optional)'),
                      onPressed: () async {
                        final result = await FilePicker.platform.pickFiles(
                          type: FileType.image,
                          withData: true,
                        );
                        if (result != null && result.files.isNotEmpty) {
                          final bytes = result.files.first.bytes;
                          if (bytes != null) {
                            setDialogState(
                                () => dialogLogo = base64Encode(bytes));
                          }
                        }
                      },
                    ),
                    if (dialogLogo.isNotEmpty)
                      const Icon(Icons.check_circle, color: Colors.green),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Abbrechen'),
            ),
            ElevatedButton(
              onPressed: () async {
                final id = idCtrl.text.trim();
                final name = nameCtrl.text.trim();
                if (id.isEmpty || name.isEmpty) return;
                Navigator.pop(ctx);
                try {
                  final payload = <String, dynamic>{
                    'application_id': id,
                    'application_name': name,
                  };
                  final url = urlCtrl.text.trim();
                  if (url.isNotEmpty) payload['api_url'] = url;
                  if (dialogLogo.isNotEmpty) {
                    payload['application_logo'] = dialogLogo;
                  }
                  final created = await _api.createCustomer(payload);
                  setState(() {
                    _allClubs.add(created);
                  });
                  _applyClub(created);
                  showInfo('Verein erstellt');
                } catch (e) {
                  showError('Fehler: $e');
                }
              },
              child: const Text('Erstellen'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final member = widget.config.member;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Verein'),
        actions: [
          if (member.isSuperAdmin)
            IconButton(
              icon: const Icon(Icons.add),
              tooltip: 'Neuen Verein erstellen',
              onPressed: _showCreateDialog,
            ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (member.isSuperAdmin && _allClubs.isNotEmpty) ...[
                    DropdownButtonFormField<String>(
                      decoration:
                          const InputDecoration(labelText: 'Verein auswählen'),
                      value: _selectedClub?['application_id'] as String?,
                      items: _allClubs.map((c) {
                        return DropdownMenuItem<String>(
                          value: c['application_id'] as String,
                          child: Text(
                            c['application_name'] as String? ??
                                c['application_id'] as String,
                          ),
                        );
                      }).toList(),
                      onChanged: (id) {
                        final club = _allClubs
                            .firstWhere((c) => c['application_id'] == id);
                        _applyClub(club);
                      },
                    ),
                    const SizedBox(height: 16),
                  ],
                  TextField(
                    controller: _nameController,
                    decoration: const InputDecoration(labelText: 'Name'),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      if (_logoBase64.isNotEmpty) ...[
                        Image.memory(
                          base64Decode(_logoBase64),
                          height: 48,
                          errorBuilder: (_, __, ___) => const SizedBox(),
                        ),
                        const SizedBox(width: 8),
                      ],
                      TextButton.icon(
                        icon: const Icon(Icons.image),
                        label: Text(
                            _logoBase64.isEmpty ? 'Logo wählen' : 'Logo ändern'),
                        onPressed: _pickLogo,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Aktive Screens',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  ..._allScreens.map((screen) {
                    final key = screen['key']!;
                    return SwitchListTile(
                      title: Text(screen['label']!),
                      value: _activeScreens.contains(key),
                      onChanged: (val) {
                        setState(() {
                          if (val) {
                            _activeScreens.add(key);
                          } else {
                            _activeScreens.remove(key);
                          }
                        });
                      },
                    );
                  }),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    icon: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child:
                                CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save),
                    label: const Text('Speichern'),
                    onPressed: _saving ? null : _save,
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 50),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
```

- [ ] **Step 2: Verify**

```bash
flutter analyze lib/screens/verein_screen.dart
```

Expected: no errors

- [ ] **Step 3: Commit**

```bash
git add lib/screens/verein_screen.dart
git commit -m "feat: add VereinScreen for club settings management"
```

---

### Task 8: Update HomeScreen — active_screens filtering and Verein tile

**Files:**
- Modify: `lib/screens/home_screen.dart`

- [ ] **Step 1: Add `_activeScreens` state field**

In `lib/screens/home_screen.dart`, add one field to `_HomeScreenState` after `_applicationLogoBase64`:

```dart
  List<String>? _activeScreens; // null = show all (backwards compatible)
```

- [ ] **Step 2: Extend `_updateApplication` to capture `active_screens`**

Replace the existing `_updateApplication` method:

```dart
  void _updateApplication() {
    CustomersApi customersApi = CustomersApi(widget.config);
    customersApi.getCustomer(widget.config.applicationId).then((customer) {
      setState(() {
        _applicationName = customer['application_name'];
        final screens = customer['active_screens'];
        if (screens != null) {
          _activeScreens = List<String>.from(screens);
        }
      });
    }).catchError((error) {
      showError("Fehler beim Laden des Vereins: $error");
    });
  }
```

- [ ] **Step 3: Add `_isScreenActive` helper**

Add this method to `_HomeScreenState` (after `_updateApplication`):

```dart
  bool _isScreenActive(String key) {
    if (_activeScreens == null) return true;
    return _activeScreens!.contains(key);
  }
```

- [ ] **Step 4: Replace `_buildGridMenu` with filtered tiles and the Verein tile**

Replace the existing `_buildGridMenu` method:

```dart
  Widget _buildGridMenu(BuildContext context, Member member) {
    final tiles = <Widget>[
      if (_isScreenActive('termine'))
        _buildMenuTile(
          context,
          '📅 Termine',
          () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => CalendarScreen(config: widget.config),
            ),
          ),
        ),
      if (_isScreenActive('marschbefehl'))
        _buildMenuTile(
          context,
          '📢 Marschbefehl',
          () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => MarschbefehlScreen(config: widget.config),
            ),
          ),
        ),
      if (_isScreenActive('strafen'))
        _buildMenuTile(
          context,
          '💰 Strafen',
          () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => StrafenScreen(config: widget.config),
            ),
          ),
        ),
      if (member.isSpiess && _isScreenActive('strafen'))
        _buildMenuTile(
          context,
          '🛡️ Spieß',
          () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => SpiessScreen(config: widget.config),
            ),
          ),
        ),
      if (_isScreenActive('dokumente'))
        _buildMenuTile(
          context,
          '📄 Dokumente',
          () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => DocumentScreen(config: widget.config),
            ),
          ),
        ),
      if (_isScreenActive('galerie'))
        _buildMenuTile(
          context,
          '📸 Fotogalerie',
          () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => GalleryScreen(config: widget.config),
            ),
          ),
        ),
      if (_isScreenActive('schere_stein_papier'))
        _buildMenuTile(
          context,
          '✂️ Schere Stein Papier',
          () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => SchereSteinPapierScreen(config: widget.config),
            ),
          ),
        ),
      if (member.isAdmin)
        _buildMenuTile(
          context,
          '👥 Mitglieder',
          () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => MitgliederScreen(config: widget.config),
            ),
          ),
        ),
      if (member.isAdmin || member.isSuperAdmin)
        _buildMenuTile(
          context,
          '🏛️ Verein',
          () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => VereinScreen(config: widget.config),
            ),
          ),
        ),
    ];

    return GridView.count(
      crossAxisCount: 2,
      childAspectRatio: 3,
      crossAxisSpacing: 8,
      mainAxisSpacing: 8,
      padding: const EdgeInsets.all(12),
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: tiles,
    );
  }
```

- [ ] **Step 5: Add the VereinScreen import**

Add this import at the top of `lib/screens/home_screen.dart` alongside the other screen imports:

```dart
import 'verein_screen.dart';
```

- [ ] **Step 6: Verify**

```bash
flutter analyze lib/screens/home_screen.dart
```

Expected: no errors

- [ ] **Step 7: Run full Flutter analysis**

```bash
flutter analyze lib/
```

Expected: no errors

- [ ] **Step 8: Commit**

```bash
git add lib/screens/home_screen.dart
git commit -m "feat: filter home screen tiles by active_screens, add Verein tile"
```
