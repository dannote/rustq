pub struct Picture;

impl Picture {
    pub fn default() -> Self {
        Picture
    }
}

impl AsRef<Picture> for Picture {
    fn as_ref(&self) -> &Picture {
        self
    }
}

pub fn consume(_picture: impl AsRef<Picture>) {}
