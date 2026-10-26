/* SPDX-License-Identifier: GPL-3.0-or-later */

#include <QFile>
#include <QFileInfo>
#include <QFileSystemWatcher>
#include <QPixmapCache>
#include <QPointer>
#include <QRegularExpression>
#include <QSettings>
#include <functional>
#include <memory>

namespace Kvantum {

class PaletteReload : public QObject
{
public:
  using Apply = std::function<bool(const QString &, const QByteArray &)>;

  PaletteReload(QObject *owner, const QString &directory, const QString &name, Apply apply)
    : QObject(owner), directory_(directory), name_(name), apply_(std::move(apply)),
      watcher_(this), timer_(this)
  {
    Snapshot initial;
    if (!read(initial))
      return;
    options_ = initial.options;
    geometry_ = geometry(initial.svg);
    generation_ = initial.generation;
    timer_.setSingleShot(true);
    timer_.setInterval(75);
    connect(&watcher_, &QFileSystemWatcher::directoryChanged, this,
            [this](const QString &) { timer_.start(); });
    connect(&timer_, &QTimer::timeout, this, [this] { reload(); });
    watcher_.addPath(QFileInfo(directory_).absolutePath());
  }

private:
  struct Snapshot {
    QString generation;
    QString config;
    QByteArray svg;
    QMap<QString, QVariant> options;
  };

  static QByteArray geometry(const QByteArray &svg)
  {
    QString shape = QString::fromUtf8(svg);
    shape.replace(QRegularExpression(QStringLiteral("#[0-9a-fA-F]{6}(?:[0-9a-fA-F]{2})?")),
                  QStringLiteral("#color"));
    return shape.toUtf8();
  }

  bool read(Snapshot &snapshot) const
  {
    QFileInfo published(directory_);
    if (!published.isSymLink())
      return false;
    snapshot.generation = published.canonicalFilePath();
    if (snapshot.generation.isEmpty())
      return false;
    snapshot.config = snapshot.generation + QLatin1Char('/') + name_ + QStringLiteral(".kvconfig");
    QFile svgFile(snapshot.generation + QLatin1Char('/') + name_ + QStringLiteral(".svg"));
    if (!QFileInfo::exists(snapshot.config) || !svgFile.open(QIODevice::ReadOnly))
      return false;
    snapshot.svg = svgFile.readAll();
    if (snapshot.svg.isEmpty())
      return false;

    QSettings settings(snapshot.config, QSettings::IniFormat);
    settings.sync();
    const QStringList keys = settings.allKeys();
    if (keys.isEmpty() || settings.status() != QSettings::NoError)
      return false;
    for (const QString &key : keys) {
      QVariant value = settings.value(key);
      if (key.endsWith(QStringLiteral(".color"))) {
        if (!QColor(value.toString()).isValid())
          return false;
        value = QString();
      }
      snapshot.options.insert(key, value);
    }
    return true;
  }

  void reload()
  {
    Snapshot candidate;
    if (!read(candidate) || candidate.generation == generation_)
      return;
    /* only colours reload in place; changed options or SVG geometry wait for an application restart. */
    if (candidate.options != options_ || geometry(candidate.svg) != geometry_)
      return;
    const Apply apply = apply_;
    QPointer<PaletteReload> self(this);
    const bool applied = apply(candidate.config, candidate.svg);
    if (self && applied)
      self->generation_ = candidate.generation;
  }

  QString directory_, name_, generation_;
  Apply apply_;
  QFileSystemWatcher watcher_;
  QTimer timer_;
  QMap<QString, QVariant> options_;
  QByteArray geometry_;
};

static QPalette
replaceThemeBrushes(QPalette palette, const QPalette &previous, const QPalette &next)
{
#if QT_VERSION >= QT_VERSION_CHECK(6, 0, 0)
  const auto mask = palette.resolveMask();
#else
  const auto mask = palette.resolve();
#endif
  for (int group = 0; group < QPalette::NColorGroups; ++group) {
    for (int role = 0; role < QPalette::NColorRoles; ++role) {
      const auto colorGroup = static_cast<QPalette::ColorGroup>(group);
      const auto colorRole = static_cast<QPalette::ColorRole>(role);
      if (palette.brush(colorGroup, colorRole) == previous.brush(colorGroup, colorRole))
        palette.setBrush(colorGroup, colorRole, next.brush(colorGroup, colorRole));
    }
  }
#if QT_VERSION >= QT_VERSION_CHECK(6, 0, 0)
  palette.setResolveMask(mask);
#else
  palette.resolve(mask);
#endif
  return palette;
}

void Style::watchPalette(const QString &theme, bool useDark)
{
  if (!themeSettings_ || !themeRndr_ || !themeRndr_->isValid())
    return;
  QStringList names;
  if (useDark) {
    QString base = theme;
    if (base.endsWith(QLatin1Char('#')))
      base.chop(1);
    names << base + QStringLiteral("Dark#") << base + QStringLiteral("Dark");
  }
  names << theme;
  for (const QString &name : names) {
    const QString directory = xdg_config_home + QStringLiteral("/Kvantum/") + name;
    if (!QFileInfo(directory).isSymLink())
      continue;
    if (!QFileInfo::exists(directory + QLatin1Char('/') + name + QStringLiteral(".kvconfig")))
      continue;
    new PaletteReload(this, directory, name,
                      [this](const QString &config, const QByteArray &svg) {
                        return reloadPalette(config, svg);
                      });
    break;
  }
}

void Style::updatePaletteContrast()
{
  hasInactiveSelItemCol_ = toggledItemHasContrast_ = false;
  if (!tspec_.no_inactiveness) {
    const label_spec label = getLabelSpec(QStringLiteral("ItemView"));
    const QColor inactive = getFromRGBA(label.toggleInactiveColor);
    const QColor active = getFromRGBA(label.toggleColor);
    if (inactive.isValid() && active.isValid() && inactive != active) {
      hasInactiveSelItemCol_ = true;
      toggledItemHasContrast_ = enoughContrast(active, getFromRGBA(label.pressColor));
    }
  }
}

bool Style::reloadPalette(const QString &config, const QByteArray &svg)
{
  auto renderer = std::unique_ptr<QSvgRenderer>(new QSvgRenderer());
  if (!renderer->load(svg))
    return false;
  auto settings = std::unique_ptr<ThemeConfig>(new ThemeConfig(config));
  settings->setParent(defaultSettings_);
  const QPalette previous = standardPalette();
  const QPalette applicationPalette = qApp->palette();
  QList<QPointer<QWidget>> explicitPalettes;
  const auto widgets = qApp->allWidgets();
  for (QWidget *widget : widgets) {
    if (widget->testAttribute(Qt::WA_SetPalette))
      explicitPalettes.append(QPointer<QWidget>(widget));
  }

  delete themeRndr_;
  delete themeSettings_;
  themeRndr_ = renderer.release();
  themeSettings_ = settings.release();
  settings_ = themeSettings_;
  cspec_ = settings_->getColorSpec();
  standardPalette_ = QPalette();
  updatePaletteContrast();
  expandedBorders_.clear();
  flatArrows_.clear();
  elements_.clear();
  drawnMenus_.clear();
  for (const QString &key : patternCacheKeys_)
    QPixmapCache::remove(key);
  patternCacheKeys_.clear();
  ++paletteRevision_;
  delete cachedOption_;
  cachedOption_ = nullptr;

  const QPalette next = standardPalette();
  QPointer<Style> self(this);
  QPointer<QStyle> activeStyle(qApp->style());
  qApp->setPalette(replaceThemeBrushes(applicationPalette, previous, next));
  if (!self || qApp->style() != activeStyle.data())
    return false;
  for (const auto &widget : explicitPalettes) {
    if (widget) {
      /* read the widget's current palette: paletteChanged callbacks may have changed its brushes. */
      widget->setPalette(replaceThemeBrushes(widget->palette(), previous, next));
      if (!self || qApp->style() != activeStyle.data())
        return false;
    }
  }
  for (QWidget *widget : qApp->allWidgets())
    widget->update();
  return true;
}

}
