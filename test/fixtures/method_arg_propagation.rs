pub struct Canvas;
pub struct Vertices;
pub struct Paint;
pub enum BlendMode { SrcOver }

impl Canvas {
    pub fn draw_vertices(&self, _vertices: &Vertices, _mode: BlendMode, _paint: &Paint) {}
}

impl Vertices {
    pub fn default() -> Self { Vertices }
}

impl Paint {
    pub fn default() -> Self { Paint }
}
