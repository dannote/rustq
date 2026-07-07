pub struct Rect;
pub struct SaveLayerRec;

impl SaveLayerRec {
    pub fn default() -> Self {
        SaveLayerRec
    }

    pub fn bounds<'a>(self, _bounds: &'a Rect) -> Self {
        self
    }
}
