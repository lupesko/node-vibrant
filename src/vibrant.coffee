###
  From Vibrant.js by Jari Zwarts
  Ported to node.js by AKFish

  Color algorithm class that finds variations on colors in an image.

  Credits
  --------
  Lokesh Dhakar (http://www.lokeshdhakar.com) - Created ColorThief
  Google - Palette support library in Android
###
Swatch = require('./swatch')
util = require('./util')

module.exports =
class Vibrant
  quantize: require('quantize')

  _swatches: []

  DefaultOpts =
    colorCount: 64
    quality: 5
    targetDarkLuma: 0.26
    maxDarkLuma: 0.45
    minLightLuma: 0.55
    targetLightLuma: 0.74
    minNormalLuma: 0.3
    targetNormalLuma: 0.5
    maxNormalLuma: 0.7
    targetMutesSaturation: 0.3
    maxMutesSaturation: 0.4
    targetVibrantSaturation: 1.0
    minVibrantSaturation: 0.35
    weightSaturation: 3
    weightLuma: 6
    weightPopulation: 1

  VibrantSwatch: undefined
  MutedSwatch: undefined
  DarkVibrantSwatch: undefined
  DarkMutedSwatch: undefined
  LightVibrantSwatch: undefined
  LightMutedSwatch: undefined

  HighestPopulation: 0

  constructor: (@sourceImage, opts = {}) ->
    @opts = util.defaults(opts, DefaultOpts)

  getSwatches: (cb) ->
    image = new @constructor.Image @sourceImage, (err, image) =>
      if err? then return cb(err)
      try
        @_process image, @opts
        cb null, @swatches()
      catch error
        return cb(error)


  _process: (image, opts) ->
    imageData = image.getImageData()
    pixels = imageData.data
    pixelCount = image.getPixelCount()

    allPixels = []
    i = 0

    while i < pixelCount
      offset = i * 4
      r = pixels[offset + 0]
      g = pixels[offset + 1]
      b = pixels[offset + 2]
      a = pixels[offset + 3]
      # If pixel is mostly opaque and not white
      if a >= 125
        if not (r > 250 and g > 250 and b > 250)
          allPixels.push [r, g, b]
      i = i + @opts.quality


    cmap = @quantize allPixels, @opts.colorCount
    @_swatches = cmap.vboxes.map (vbox) =>
      new Swatch vbox.color, vbox.vbox.count()

    @maxPopulation = @findMaxPopulation

    @generateVarationColors()
    @generateEmptySwatches()

    # Clean up
    image.removeCanvas()

  generateVarationColors: ->
    @VibrantSwatch = @findColorVariation(@opts.targetNormalLuma, @opts.minNormalLuma, @opts.maxNormalLuma,
      @opts.targetVibrantSaturation, @opts.minVibrantSaturation, 1);

    @LightVibrantSwatch = @findColorVariation(@opts.targetLightLuma, @opts.minLightLuma, 1,
      @opts.targetVibrantSaturation, @opts.minVibrantSaturation, 1);

    @DarkVibrantSwatch = @findColorVariation(@opts.targetDarkLuma, 0, @opts.maxDarkLuma,
      @opts.targetVibrantSaturation, @opts.minVibrantSaturation, 1);

    @MutedSwatch = @findColorVariation(@opts.targetNormalLuma, @opts.minNormalLuma, @opts.maxNormalLuma,
      @opts.targetMutesSaturation, 0, @opts.maxMutesSaturation);

    @LightMutedSwatch = @findColorVariation(@opts.targetLightLuma, @opts.minLightLuma, 1,
      @opts.targetMutesSaturation, 0, @opts.maxMutesSaturation);

    @DarkMutedSwatch = @findColorVariation(@opts.targetDarkLuma, 0, @opts.maxDarkLuma,
      @opts.targetMutesSaturation, 0, @opts.maxMutesSaturation);

  generateEmptySwatches: ->
    if @VibrantSwatch is undefined
      # If we do not have a vibrant color...
      if @DarkVibrantSwatch isnt undefined
        # ...but we do have a dark vibrant, generate the value by modifying the luma
        hsl = @DarkVibrantSwatch.getHsl()
        hsl[2] = @opts.targetNormalLuma
        @VibrantSwatch = new Swatch util.hslToRgb(hsl[0], hsl[1], hsl[2]), 0

    if @DarkVibrantSwatch is undefined
      # If we do not have a vibrant color...
      if @VibrantSwatch isnt undefined
        # ...but we do have a dark vibrant, generate the value by modifying the luma
        hsl = @VibrantSwatch.getHsl()
        hsl[2] = @opts.targetDarkLuma
        @DarkVibrantSwatch = new Swatch util.hslToRgb(hsl[0], hsl[1], hsl[2]), 0

  findMaxPopulation: ->
    population = 0
    population = Math.max(population, swatch.getPopulation()) for swatch in @_swatches
    population

  findColorVariation: (targetLuma, minLuma, maxLuma, targetSaturation, minSaturation, maxSaturation) ->
    max = undefined
    maxValue = 0

    for swatch in @_swatches
      sat = swatch.getHsl()[1];
      luma = swatch.getHsl()[2]

      if sat >= minSaturation and sat <= maxSaturation and
        luma >= minLuma and luma <= maxLuma and
        not @isAlreadySelected(swatch)
          value = @createComparisonValue sat, targetSaturation, luma, targetLuma,
            swatch.getPopulation(), @HighestPopulation
          if max is undefined or value > maxValue
            max = swatch
            maxValue = value

    max

  createComparisonValue: (saturation, targetSaturation,
      luma, targetLuma, population, maxPopulation) ->
    @weightedMean(
      @invertDiff(saturation, targetSaturation), @opts.weightSaturation,
      @invertDiff(luma, targetLuma), @opts.weightLuma,
      population / maxPopulation, @opts.weightPopulation
    )

  invertDiff: (value, targetValue) ->
    1 - Math.abs value - targetValue

  weightedMean: (values...) ->
    sum = 0
    sumWeight = 0
    i = 0
    while i < values.length
      value = values[i]
      weight = values[i + 1]
      sum += value * weight
      sumWeight += weight
      i += 2
    sum / sumWeight

  swatches: =>
      Vibrant: @VibrantSwatch
      Muted: @MutedSwatch
      DarkVibrant: @DarkVibrantSwatch
      DarkMuted: @DarkMutedSwatch
      LightVibrant: @LightVibrantSwatch
      LightMuted: @LightMuted

  isAlreadySelected: (swatch) ->
    @VibrantSwatch is swatch or @DarkVibrantSwatch is swatch or
      @LightVibrantSwatch is swatch or @MutedSwatch is swatch or
      @DarkMutedSwatch is swatch or @LightMutedSwatch is swatch
