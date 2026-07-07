pub struct Paint;
pub struct ImageFilter;
pub struct RuntimeEffect;
pub struct Matrix;
pub struct Shader;

impl Paint {
    pub fn set_image_filter(&mut self, _image_filter: impl Into<Option<ImageFilter>>) {}
}

impl RuntimeEffect {
    pub fn make_shader<'a>(&self, _matrix: impl Into<Option<&'a Matrix>>) -> Option<Shader> {
        None
    }
}
