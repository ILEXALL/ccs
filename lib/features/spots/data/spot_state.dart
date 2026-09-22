import 'package:flutter/material.dart' hide Text;
import 'package:latlong2/latlong.dart';
import 'package:ccs_app/features/spots/models/car_spot.dart' show CarSpot;
import 'package:ccs_app/features/spots/models/spot_status.dart' show SpotStatus;

final submittedSpots = ValueNotifier<List<CarSpot>>([]);

final savedSpots = ValueNotifier<List<CarSpot>>([]);

final reviewSpots = ValueNotifier<List<CarSpot>>([]);

const demoSpots = [
  CarSpot(
    name: 'Andrejsala Harbor',
    cityCountry: 'Riga, Latvia',
    coordinates: LatLng(56.9612, 24.0944),
    description:
        'Industrial harbor mood, wide roads, dark water reflections, and a strong night shoot atmosphere.',
    categories: ['Photo', 'Reels', 'Meet'],
    photoUrl:
        'https://images.unsplash.com/photo-1492144534655-ae79c964c9d7?q=80&w=1200&auto=format&fit=crop',
    reelLink: 'https://instagram.com/reel/demo-andrejsala',
    bestTime: 'Night',
    parking: 'Easy',
    roadQuality: 'Good',
    lowCarFriendly: true,
    policeRisk: 'Medium',
    traffic: 'Low',
    lighting: 'Street lights',
    crowd: 'Medium',
    addedBy: 'riga_driver',
    status: SpotStatus.approved,
  ),
  CarSpot(
    name: 'Spikeri Brick Yard',
    cityCountry: 'Riga, Latvia',
    coordinates: LatLng(56.9427, 24.1168),
    description:
        'Brick walls, city texture, and clean angles for rollers, portraits, and parked car shots.',
    categories: ['Photo', 'Reels'],
    photoUrl:
        'https://images.unsplash.com/photo-1542362567-b07e54358753?q=80&w=1200&auto=format&fit=crop',
    reelLink: 'https://tiktok.com/@ccs/video/demo-spikeri',
    bestTime: 'Golden hour',
    parking: 'Street',
    roadQuality: 'Mixed',
    lowCarFriendly: false,
    policeRisk: 'Low',
    traffic: 'Medium',
    lighting: 'Warm city lights',
    crowd: 'Low',
    addedBy: 'stance_lv',
    status: SpotStatus.approved,
  ),
  CarSpot(
    name: 'Bikernieki Forest Road',
    cityCountry: 'Riga, Latvia',
    coordinates: LatLng(56.9662, 24.2294),
    description:
        'Forest road energy near the track area. Best for clean rolling content and small meets.',
    categories: ['Drive', 'Meet', 'Reels'],
    photoUrl:
        'https://images.unsplash.com/photo-1503736334956-4c8f8e92946d?q=80&w=1200&auto=format&fit=crop',
    reelLink: 'https://instagram.com/reel/demo-bikernieki',
    bestTime: 'Evening',
    parking: 'Good',
    roadQuality: 'Good',
    lowCarFriendly: true,
    policeRisk: 'Low',
    traffic: 'Low',
    lighting: 'Natural',
    crowd: 'Low',
    addedBy: 'jdm_riga',
    status: SpotStatus.approved,
  ),
  CarSpot(
    name: 'Riga Rooftop Parking',
    cityCountry: 'Riga, Latvia',
    coordinates: LatLng(56.9497, 24.1052),
    description:
        'Skyline view and clean concrete lines. This spot is waiting for moderator approval.',
    categories: ['Photo', 'Low car'],
    photoUrl:
        'https://images.unsplash.com/photo-1511919884226-fd3cad34687c?q=80&w=1200&auto=format&fit=crop',
    reelLink: 'https://instagram.com/reel/demo-pending',
    bestTime: 'Sunset',
    parking: 'Private',
    roadQuality: 'Good',
    lowCarFriendly: true,
    policeRisk: 'High',
    traffic: 'Medium',
    lighting: 'Rooftop lights',
    crowd: 'Unknown',
    addedBy: 'new_spotter',
    status: SpotStatus.pending,
  ),
];
