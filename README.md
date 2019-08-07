# MetalPicking

This is the sample code for the article [_Picking and Hit-Testing in Metal_](http://metalbyexample.com/picking-hit-testing/) on _Metal by Example_.

![Demonstration of picking in sample app](http://d2jaiao3zdxbzm.cloudfront.net/wp-content/uploads/picking.gif)

## Modifications by [rudifa](https://github.com/rudifa)

Changed from `func makeScene()` to `func makeScene_xyz_spheres(gridSideCountX:gridSideCountY:gridSideCountZ:)`, activated the 3rd dimension, factored out computations into `positionOnAxis(ijk:gridSideCount:)`

Added `handlePan(recognizer:)` and moved it along with  `handleTapClick(recognizer:)` into a separate `extension ViewController: NSUIGestureRecognizerDelegate {...}`.

Moved the bi-platform adpter code (iOS | macOS) into a separate file `BiPlatformExtensions.swift`.



