//
//  ConcurrencyShims.swift
//  ShadowVM
//
//  Created by Saagar Jha on 6/12/22.
//

import Foundation

func unsafelyRunOnMainActor<T>(_ work: @MainActor () throws -> T) rethrows -> T {
  assert(Thread.isMainThread)
  return try _unsafelyRunOnMainActor(work)
}

@preconcurrency @MainActor
func _unsafelyRunOnMainActor<T>(_ work: @MainActor () throws -> T) rethrows -> T {
  try work()
}
