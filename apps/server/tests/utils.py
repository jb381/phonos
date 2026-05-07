import io
import struct


def generate_silent_wav(duration_seconds: float = 1.0, sample_rate: int = 16000) -> io.BytesIO:
    """Generate a silent 16-bit mono WAV file in memory.

    Args:
        duration_seconds: Length of the audio in seconds.
        sample_rate: Sample rate in Hz.

    Returns:
        A ``BytesIO`` buffer seeked to the beginning.
    """
    num_samples = int(sample_rate * duration_seconds)
    buf = io.BytesIO()

    buf.write(b"RIFF")
    buf.write(struct.pack("<I", 36 + num_samples * 2))
    buf.write(b"WAVE")
    buf.write(b"fmt ")
    buf.write(struct.pack("<I", 16))
    buf.write(struct.pack("<HH", 1, 1))
    buf.write(struct.pack("<I", sample_rate))
    buf.write(struct.pack("<I", sample_rate * 2))
    buf.write(struct.pack("<HH", 2, 16))
    buf.write(b"data")
    buf.write(struct.pack("<I", num_samples * 2))
    buf.write(b"\x00\x00" * num_samples)

    buf.seek(0)
    return buf
