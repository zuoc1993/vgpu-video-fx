//! RGBA8 frame buffers (top-left origin).

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Frame {
    pub width: u32,
    pub height: u32,
    pub data: Vec<u8>,
}

impl Frame {
    pub fn new(width: u32, height: u32) -> Self {
        Frame {
            width,
            height,
            data: vec![0u8; width as usize * height as usize * 4],
        }
    }

    pub fn from_bytes(width: u32, height: u32, data: &[u8]) -> crate::Result<Self> {
        let need = width as usize * height as usize * 4;
        if data.len() < need {
            return Err(crate::EffectError::new(format!(
                "RGBA buffer too small: {} < {need}",
                data.len()
            )));
        }
        Ok(Frame {
            width,
            height,
            data: data[..need].to_vec(),
        })
    }

    pub fn view(&self) -> FrameView<'_> {
        FrameView {
            width: self.width,
            height: self.height,
            data: &self.data,
        }
    }

    pub fn view_mut(&mut self) -> FrameViewMut<'_> {
        FrameViewMut {
            width: self.width,
            height: self.height,
            data: &mut self.data,
        }
    }
}

#[derive(Clone, Copy)]
pub struct FrameView<'a> {
    pub width: u32,
    pub height: u32,
    pub data: &'a [u8],
}

impl<'a> FrameView<'a> {
    #[inline]
    pub fn texel(&self, x: u32, y: u32) -> [u8; 4] {
        let i = ((y * self.width + x) * 4) as usize;
        [
            self.data[i],
            self.data[i + 1],
            self.data[i + 2],
            self.data[i + 3],
        ]
    }
}

pub struct FrameViewMut<'a> {
    pub width: u32,
    pub height: u32,
    pub data: &'a mut [u8],
}

impl<'a> FrameViewMut<'a> {
    #[inline]
    pub fn row(&mut self, y: u32) -> &mut [u8] {
        let w = self.width as usize * 4;
        let start = y as usize * w;
        &mut self.data[start..start + w]
    }

    #[inline]
    pub fn put(&mut self, x: u32, y: u32, c: [f32; 4]) {
        let i = ((y * self.width + x) * 4) as usize;
        self.data[i] = to_u8(c[0]);
        self.data[i + 1] = to_u8(c[1]);
        self.data[i + 2] = to_u8(c[2]);
        self.data[i + 3] = to_u8(c[3]);
    }
}

/// rgba8unorm store: clamp to [0, 1], scale by 255, round to nearest.
#[inline]
pub fn to_u8(v: f32) -> u8 {
    (v.clamp(0.0, 1.0) * 255.0).round() as u8
}
