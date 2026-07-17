/// Averages recorded per-sample spectral profiles into one reference profile
/// for the detector.
///
/// Inputs: [sampleProfiles] one spectral profile (see
/// `computeSpectralProfile` in `spectral_profile.dart`) per recorded
/// calibration sample shot.
/// Outputs: the band-wise mean profile.
List<double> deriveReferenceProfile(List<List<double>> sampleProfiles) {
  if (sampleProfiles.isEmpty) {
    throw ArgumentError('Need at least one sample profile to derive a reference profile.');
  }

  final bandCount = sampleProfiles.first.length;
  final averaged = List<double>.filled(bandCount, 0.0);
  for (final profile in sampleProfiles) {
    for (var i = 0; i < bandCount; i++) {
      averaged[i] += profile[i];
    }
  }
  for (var i = 0; i < bandCount; i++) {
    averaged[i] /= sampleProfiles.length;
  }
  return averaged;
}
