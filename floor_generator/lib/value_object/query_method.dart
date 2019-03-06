import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:floor_generator/misc/constants.dart';
import 'package:floor_generator/misc/type_utils.dart';
import 'package:floor_generator/value_object/entity.dart';
import 'package:source_gen/source_gen.dart';

/// Wraps a method annotated with Query
/// to enable easy access to code generation relevant data.
class QueryMethod {
  final MethodElement method;

  QueryMethod(final this.method);

  /// Query as defined in by user in Dart code.
  String get _rawQuery {
    final query = method.metadata
        .firstWhere(isQueryAnnotation)
        .computeConstantValue()
        .getField(AnnotationField.QUERY_VALUE)
        .toStringValue();

    if (query.isEmpty || query == null) {
      throw InvalidGenerationSourceError(
        "You didn't define a query.",
        element: method,
      );
    }

    return query;
  }

  /// Query where ':' got replaced with '$'.
  String get query => _rawQuery.replaceAll(RegExp(':'), r'$');

  List<String> get queryParameterNames {
    return RegExp(r'\$.[^\s]+')
        .allMatches(query)
        .map((match) => match.group(0).replaceFirst(RegExp(r'\$'), ''))
        .toList();
  }

  String get name => method.displayName;

  DartType get rawReturnType => method.returnType;

  /// Flattened return type.
  ///
  /// E.g.
  /// Future<T> -> T,
  /// Future<List<T>> -> T
  ///
  /// Stream<T> -> T
  /// Stream<List<T>> -> T
  DartType get flattenedReturnType {
    final type = returnsStream
        ? flattenStream(method.returnType)
        : method.returnType.flattenFutures(method.context.typeSystem);
    if (returnsList) {
      return flattenList(type);
    }
    return type;
  }

  List<ParameterElement> get parameters => method.parameters;

  bool get returnsList {
    final type = returnsStream
        ? flattenStream(method.returnType)
        : method.returnType.flattenFutures(method.context.typeSystem);

    return isList(type);
  }

  bool get returnsVoid {
    final type = returnsStream
        ? flattenStream(method.returnType)
        : method.returnType.flattenFutures(method.context.typeSystem);

    return type.isVoid;
  }

  bool get returnsStream => isStream(method.returnType);

  Entity _entityCache;

  Entity getEntity(final LibraryReader library) {
    if (_entityCache != null) return _entityCache;

    final entity = _getEntities(library).firstWhere(
        (entity) => entity.displayName == flattenedReturnType.displayName,
        orElse: () => null); // doesn't return an entity

    return _entityCache ??= entity != null ? Entity(entity) : null;
  }

  bool returnsEntity(final LibraryReader library) {
    final entities =
        _getEntities(library).map((clazz) => clazz.displayName).toList();

    return entities.any((entity) => entity == flattenedReturnType.displayName);
  }

  List<ClassElement> _getEntities(final LibraryReader library) {
    return library.classes
        .where((clazz) =>
            !clazz.isAbstract && clazz.metadata.any(isEntityAnnotation))
        .toList();
  }
}