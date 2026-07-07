pub struct Paint;
pub struct ImageFilter;

impl Paint {
    pub fn set_image_filter(&mut self, _image_filter: impl Into<Option<ImageFilter>>) {}
}
