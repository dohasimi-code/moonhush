package com.moonhush.app

import com.ryanheise.audioservice.AudioServiceActivity

// Shares the Flutter engine with the background audio service so playback
// survives the app being closed.
class MainActivity : AudioServiceActivity()
