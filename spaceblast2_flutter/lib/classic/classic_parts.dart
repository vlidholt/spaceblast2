// Visual building blocks of the original 2D Space Blast (SpriteWidget),
// copied from reference/spaceblast with only the game logic removed: the
// split-screen demo drives them from the shared GameWorld instead.
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:spritewidget/spritewidget.dart';

/// Sprite sheets and images of the original game.
class ClassicAssets {
  ClassicAssets._(this.images, this.sprites, this.ui);

  final ImageMap images;
  final SpriteSheet sprites;
  final SpriteSheet ui;

  static Future<ClassicAssets> load() async {
    final images = ImageMap();
    await images.load(<String>[
      'assets/classic/nebula.png',
      'assets/classic/sprites.png',
      'assets/classic/starfield.png',
      'assets/classic/game_ui.png',
      'assets/classic/ui_bg_top.png',
      'assets/classic/ui_bg_bottom.png',
    ]);
    final sprites = SpriteSheet(
      image: images['assets/classic/sprites.png']!,
      jsonDefinition: await rootBundle.loadString(
        'assets/classic/sprites.json',
      ),
    );
    final uiSheet = SpriteSheet(
      image: images['assets/classic/game_ui.png']!,
      jsonDefinition: await rootBundle.loadString(
        'assets/classic/game_ui.json',
      ),
    );
    return ClassicAssets._(images, sprites, uiSheet);
  }
}

const List<Color> classicLaserColors = [
  Color(0xff95f4fb),
  Color(0xff5bff35),
  Color(0xffff886c),
  Color(0xffffd012),
  Color(0xfffd7fff),
];

void addLaserSprites(Node node, int level, double r, SpriteSheet sheet) {
  final numLasers = level % 3 + 1;
  final laserColor =
      classicLaserColors[(level ~/ 3) % classicLaserColors.length];

  final sprites = <Sprite>[];
  for (int i = 0; i < numLasers; i++) {
    final sprite = Sprite(texture: sheet['explosion_particle.png']!);
    sprite.scale = 0.5;
    sprite.colorOverlay = laserColor;
    sprite.blendMode = ui.BlendMode.plus;
    node.addChild(sprite);
    sprites.add(sprite);
  }

  if (numLasers == 2) {
    sprites[0].position = const Offset(-3.0, 0.0);
    sprites[1].position = const Offset(3.0, 0.0);
  } else if (numLasers == 3) {
    sprites[0].position = const Offset(-4.0, 0.0);
    sprites[1].position = const Offset(4.0, 0.0);
    sprites[2].position = const Offset(0.0, -2.0);
  }
}

Color colorForDamage(double damage, double maxDamage, [Color? toColor]) {
  int r, g, b;
  if (toColor == null) {
    r = 255;
    g = 3;
    b = 86;
  } else {
    r = (toColor.r * 255).round();
    g = (toColor.g * 255).round();
    b = (toColor.b * 255).round();
  }
  final alpha = ((200.0 * damage) ~/ maxDamage).clamp(0, 200);
  return Color.fromARGB(alpha, r, g, b);
}

class Explosion extends Node {
  Explosion() {
    zPosition = 10.0;
  }
}

class ExplosionBig extends Explosion {
  ExplosionBig(SpriteSheet sheet) {
    final particlesDebris = ParticleSystem(
      texture: sheet['explosion_particle.png']!,
      rotateToMovement: true,
      startRotation: 90.0,
      startRotationVar: 0.0,
      endRotation: 90.0,
      startSize: 0.3,
      startSizeVar: 0.1,
      endSize: 0.3,
      endSizeVar: 0.1,
      numParticlesToEmit: 25,
      emissionRate: 1000.0,
      greenVar: 127,
      redVar: 127,
      life: 0.75,
      lifeVar: 0.5,
    );
    particlesDebris.zPosition = 1010.0;
    addChild(particlesDebris);

    final particlesFire = ParticleSystem(
      texture: sheet['fire_particle.png']!,
      colorSequence: ColorSequence(
        colors: const [Color(0xffffff33), Color(0xffff3333), Color(0x00ff3333)],
        stops: const [0.0, 0.5, 1.0],
      ),
      numParticlesToEmit: 25,
      emissionRate: 1000.0,
      startSize: 0.5,
      startSizeVar: 0.1,
      endSize: 0.5,
      endSizeVar: 0.1,
      posVar: const Offset(10.0, 10.0),
      speed: 10.0,
      speedVar: 5.0,
      life: 0.75,
      lifeVar: 0.5,
    );
    particlesFire.zPosition = 1011.0;
    addChild(particlesFire);

    final spriteRing = Sprite(texture: sheet['explosion_ring.png']!);
    spriteRing.blendMode = ui.BlendMode.plus;
    addChild(spriteRing);

    final scale = MotionTween<double>(
      setter: (a) => spriteRing.scale = a,
      start: 0.2,
      end: 1.0,
      duration: 0.75,
    );
    motions.run(
      MotionSequence(
        motions: <Motion>[
          scale,
          MotionRemoveNode(node: spriteRing),
        ],
      ),
    );
    motions.run(
      MotionTween<double>(
        setter: (a) => spriteRing.opacity = a,
        start: 1.0,
        end: 0.0,
        duration: 0.75,
      ),
    );

    for (int i = 0; i < 5; i++) {
      final spriteFlare = Sprite(texture: sheet['explosion_flare.png']!);
      spriteFlare.pivot = const Offset(0.3, 1.0);
      spriteFlare.scaleX = 0.3;
      spriteFlare.blendMode = ui.BlendMode.plus;
      spriteFlare.rotation = randomDouble() * 360.0;
      addChild(spriteFlare);

      final multiplier = randomDouble() * 0.3 + 1.0;

      motions.run(
        MotionSequence(
          motions: [
            MotionTween<double>(
              setter: (a) => spriteFlare.scaleY = a,
              start: 0.3 * multiplier,
              end: 0.8,
              duration: 0.75 * multiplier,
            ),
            MotionRemoveNode(node: spriteFlare),
          ],
        ),
      );
      motions.run(
        MotionSequence(
          motions: [
            MotionTween<double>(
              setter: (a) => spriteFlare.opacity = a,
              start: 0.0,
              end: 1.0,
              duration: 0.25 * multiplier,
            ),
            MotionTween<double>(
              setter: (a) => spriteFlare.opacity = a,
              start: 1.0,
              end: 0.0,
              duration: 0.5 * multiplier,
            ),
          ],
        ),
      );
    }

    // Tidy up once everything has played out.
    motions.run(
      MotionSequence(
        motions: [
          MotionDelay(delay: 2.5),
          MotionRemoveNode(node: this),
        ],
      ),
    );
  }
}

class ExplosionMini extends Explosion {
  ExplosionMini(SpriteSheet sheet) {
    for (int i = 0; i < 2; i++) {
      final star = Sprite(texture: sheet['star_0.png']!);
      star.scale = 0.5;
      star.colorOverlay = const Color(0xff95f4fb);
      star.blendMode = ui.BlendMode.plus;
      addChild(star);

      double rotationStart = randomDouble() * 90.0;
      double rotationEnd = 180.0 + randomDouble() * 90.0;
      if (i == 0) {
        rotationStart = -rotationStart;
        rotationEnd = -rotationEnd;
      }

      motions.run(
        MotionTween<double>(
          setter: (a) => star.rotation = a,
          start: rotationStart,
          end: rotationEnd,
          duration: 0.2,
        ),
      );
      motions.run(
        MotionTween<double>(
          setter: (a) => star.opacity = a,
          start: 1.0,
          end: 0.0,
          duration: 0.2,
        ),
      );
    }

    motions.run(
      MotionSequence(
        motions: [
          MotionDelay(delay: 0.2),
          MotionRemoveNode(node: this),
        ],
      ),
    );
  }
}

class Flash extends NodeWithSize {
  Flash(super.size, this.duration) {
    motions.run(
      MotionSequence(
        motions: <Motion>[
          MotionTween<double>(
            setter: (a) => _opacity = a,
            start: 1.0,
            end: 0.0,
            duration: duration,
          ),
          MotionRemoveNode(node: this),
        ],
      ),
    );
  }

  double duration;
  double _opacity = 1.0;
  final Paint _cachedPaint = Paint();

  @override
  void paint(Canvas canvas) {
    _cachedPaint.color = Color.fromARGB(
      (255.0 * _opacity).toInt(),
      255,
      255,
      255,
    );
    applyTransformForPivot(canvas);
    canvas.drawRect(
      Rect.fromLTRB(0.0, 0.0, size.width, size.height),
      _cachedPaint,
    );
  }
}

class PowerBar extends NodeWithSize {
  PowerBar(super.size);

  double power = 1.0;

  final Paint _paintFill = Paint()..color = const Color(0xffffffff);
  final Paint _paintOutline = Paint()
    ..color = const Color(0xffffffff)
    ..strokeWidth = 1.0
    ..style = ui.PaintingStyle.stroke;

  @override
  void paint(Canvas canvas) {
    applyTransformForPivot(canvas);
    canvas.drawRect(
      Rect.fromLTRB(0.0, 0.0, size.width, size.height),
      _paintOutline,
    );
    canvas.drawRect(
      Rect.fromLTRB(2.0, 2.0, (size.width - 2.0) * power, size.height - 2.0),
      _paintFill,
    );
  }
}

class RepeatedImage extends Node {
  RepeatedImage(ui.Image image, [ui.BlendMode? mode]) {
    _sprite0 = Sprite.fromImage(image);
    _sprite0.size = const Size(1024.0, 1024.0);
    _sprite0.pivot = Offset.zero;
    _sprite1 = Sprite.fromImage(image);
    _sprite1.size = const Size(1024.0, 1024.0);
    _sprite1.pivot = Offset.zero;
    _sprite1.position = const Offset(0.0, -1024.0);

    if (mode != null) {
      _sprite0.blendMode = mode;
      _sprite1.blendMode = mode;
    }

    addChild(_sprite0);
    addChild(_sprite1);
  }

  late Sprite _sprite0;
  late Sprite _sprite1;

  void move(double dy) {
    final yPos = (position.dy + dy) % 1024.0;
    position = Offset(0.0, yPos);
  }
}

class StarField extends NodeWithSize {
  StarField(this._spriteSheet, this._numStars, [this._autoScroll = false])
    : super(Size.zero) {
    _image = _spriteSheet.image;
    addStars();
  }

  late ui.Image _image;
  final SpriteSheet _spriteSheet;
  final int _numStars;
  final bool _autoScroll;

  List<Offset> _starPositions = [];
  List<double> _starScales = [];
  List<Rect> _rects = [];
  List<Color> _colors = [];

  final double _padding = 50.0;
  Size _paddedSize = Size.zero;

  final Paint _paint = Paint()
    ..filterQuality = ui.FilterQuality.low
    ..isAntiAlias = false
    ..blendMode = ui.BlendMode.plus;

  void addStars() {
    _starPositions = [];
    _starScales = [];
    _colors = [];
    _rects = [];

    size = spriteBox == null
        ? const Size(2048, 2048)
        : spriteBox!.visibleArea!.size;
    _paddedSize = Size(
      size.width + _padding * 2.0,
      size.height + _padding * 2.0,
    );

    for (int i = 0; i < _numStars; i++) {
      _starPositions.add(
        Offset(
          randomDouble() * _paddedSize.width,
          randomDouble() * _paddedSize.height,
        ),
      );
      _starScales.add(randomDouble() * 0.4);
      _colors.add(
        Color.fromARGB(
          (255.0 * (randomDouble() * 0.5 + 0.5)).toInt(),
          255,
          255,
          255,
        ),
      );
      _rects.add(_spriteSheet['star_${randomInt(2)}.png']!.frame);
    }
  }

  @override
  void spriteBoxPerformedLayout() => addStars();

  @override
  void paint(Canvas canvas) {
    final transforms = <ui.RSTransform>[
      for (int i = 0; i < _numStars; i++)
        ui.RSTransform(
          _starScales[i],
          0.0,
          _starPositions[i].dx - _padding,
          _starPositions[i].dy - _padding,
        ),
    ];
    canvas.drawAtlas(
      _image,
      transforms,
      _rects,
      _colors,
      ui.BlendMode.modulate,
      null,
      _paint,
    );
  }

  void move(double dx, double dy) {
    for (int i = 0; i < _numStars; i++) {
      double xPos = _starPositions[i].dx;
      double yPos = _starPositions[i].dy;
      final scale = _starScales[i];

      xPos += dx * scale;
      yPos += dy * scale;

      if (xPos >= _paddedSize.width) xPos -= _paddedSize.width;
      if (xPos < 0) xPos += _paddedSize.width;
      if (yPos >= _paddedSize.height) yPos -= _paddedSize.height;
      if (yPos < 0) yPos += _paddedSize.height;

      _starPositions[i] = Offset(xPos, yPos);
    }
  }

  @override
  void update(double dt) {
    if (_autoScroll) move(0.0, dt * 100.0);
  }
}

class TextureImage extends StatelessWidget {
  const TextureImage({
    super.key,
    required this.texture,
    this.width = 128.0,
    this.height = 128.0,
  });

  final SpriteTexture texture;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: CustomPaint(painter: _TextureImagePainter(texture)),
    );
  }
}

class _TextureImagePainter extends CustomPainter {
  _TextureImagePainter(this.texture);

  final SpriteTexture texture;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(
      size.width / texture.size.width,
      size.height / texture.size.height,
    );
    texture.drawTexture(canvas, Offset.zero, Paint());
    canvas.restore();
  }

  @override
  bool shouldRepaint(_TextureImagePainter oldDelegate) =>
      oldDelegate.texture != texture;
}

class TextureButton extends StatefulWidget {
  const TextureButton({
    super.key,
    required this.onPressed,
    required this.texture,
    this.width = 128.0,
    this.height = 128.0,
    this.label,
    this.textStyle,
    this.labelOffset = Offset.zero,
  });

  final VoidCallback onPressed;
  final SpriteTexture texture;
  final TextStyle? textStyle;
  final String? label;
  final double width;
  final double height;
  final Offset labelOffset;

  @override
  State<TextureButton> createState() => _TextureButtonState();
}

class _TextureButtonState extends State<TextureButton> {
  bool _highlight = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _highlight = true),
      onTap: () {
        setState(() => _highlight = false);
        widget.onPressed();
      },
      onTapCancel: () => setState(() => _highlight = false),
      child: SizedBox(
        width: widget.width,
        height: widget.height,
        child: CustomPaint(
          painter: _TextureButtonPainter(widget, _highlight),
        ),
      ),
    );
  }
}

class _TextureButtonPainter extends CustomPainter {
  _TextureButtonPainter(this.config, this.highlight);

  final TextureButton config;
  final bool highlight;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(
      size.width / config.texture.size.width,
      size.height / config.texture.size.height,
    );
    config.texture.drawTexture(
      canvas,
      Offset.zero,
      highlight
          ? (Paint()
              ..colorFilter = const ColorFilter.mode(
                Color(0x66000000),
                BlendMode.srcATop,
              ))
          : Paint(),
    );
    canvas.restore();

    final label = config.label;
    if (label != null) {
      final painter = TextPainter(
        text: TextSpan(
          style:
              config.textStyle ??
              const TextStyle(fontSize: 24.0, fontWeight: FontWeight.w700),
          text: label,
        ),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
      );
      painter.layout(minWidth: size.width, maxWidth: size.width);
      painter.paint(
        canvas,
        Offset(0.0, size.height / 2.0 - painter.height / 2.0) +
            config.labelOffset,
      );
    }
  }

  @override
  bool shouldRepaint(_TextureButtonPainter oldDelegate) =>
      oldDelegate.highlight != highlight ||
      oldDelegate.config.label != config.label ||
      oldDelegate.config.texture != config.texture;
}
