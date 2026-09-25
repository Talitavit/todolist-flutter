/// A user-defined task category, persisted in the `categories` table.
class Category {
  final int? id;
  final String name;

  /// ARGB color used for the category chip/badge.
  final int colorValue;

  const Category({this.id, required this.name, required this.colorValue});

  Category copyWith({int? id, String? name, int? colorValue}) => Category(
        id: id ?? this.id,
        name: name ?? this.name,
        colorValue: colorValue ?? this.colorValue,
      );

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'name': name,
        'color': colorValue,
      };

  factory Category.fromMap(Map<String, Object?> map) => Category(
        id: map['id'] as int,
        name: map['name'] as String,
        colorValue: map['color'] as int,
      );

  /// Palette offered when creating a category; cycled by index.
  static const palette = <int>[
    0xFF1E88E5, // blue
    0xFF43A047, // green
    0xFFFB8C00, // orange
    0xFF8E24AA, // purple
    0xFFE53935, // red
    0xFF00897B, // teal
    0xFF6D4C41, // brown
    0xFF3949AB, // indigo
  ];
}
