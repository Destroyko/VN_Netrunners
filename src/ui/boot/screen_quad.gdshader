shader_type canvas_item;
// Натянуть экран ПК (буфер загрузки) на монитор в перспективе: точка на экране игрока →
// обратная гомография → точка в буфере. Вне монитора ничего не рисуем.

uniform mat3 screen_to_uv;
uniform vec2 view_size;

void fragment() {
	vec3 q = screen_to_uv * vec3(UV * view_size, 1.0);
	vec2 uv = q.xy / q.z;
	if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
		discard;
	}
	COLOR = texture(TEXTURE, uv);
}
