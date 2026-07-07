pub struct Paint;
pub struct SaveLayerRec;

impl Paint {
    pub fn default() -> Self {
        Paint
    }
}

impl SaveLayerRec {
    pub fn default() -> Self {
        SaveLayerRec
    }

    pub fn paint(self, _paint: &Paint) -> Self {
        self
    }
}
