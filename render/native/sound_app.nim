import yantra

var clickSnd: Sound
var badSnd: Sound

app("SoundApp", width = 400, height = 300):
  clickSnd = sound("click.wav")
  badSnd = sound("../secret.wav")
  column(gap = 10, padding = 16):
    button "Play":
      onClick:
        setVolume(clickSnd, 1.0'f32)
        play(clickSnd)
    button "Half":
      onClick:
        setVolume(clickSnd, 0.25'f32)
        log($volume(clickSnd))
        play(clickSnd)
    button "Stop":
      onClick:
        stop(clickSnd)
    button "Bad":
      onClick:
        play(badSnd)
