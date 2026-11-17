/*
 * Copyright The OpenTelemetry Authors
 * SPDX-License-Identifier: Apache-2.0
 */

import Foundation

struct Batch {
  /// Data read from file
  let data: Data
  /// File from which `data` was read.
  let file: ReadableFile
}

protocol FileReader {
  func readNextBatch() -> Batch?

  func onRemainingBatches(process: (Batch) -> Void) -> Bool

  func markBatchAsRead(_ batch: Batch)
}

final class OrchestratedFileReader: FileReader {
  /// Orchestrator producing reference to readable file.
  private let orchestrator: FilesOrchestrator

  /// Names of files marked as read that could not be deleted, so they are not exported again.
  private(set) var undeletedFileNames: Set<String> = []

  init(orchestrator: FilesOrchestrator) {
    self.orchestrator = orchestrator
  }

  // MARK: - Reading batches

  func readNextBatch() -> Batch? {
    if let file = orchestrator.getReadableFile(excludingFilesNamed: undeletedFileNames) {
      do {
        let fileData = try file.read()
        return Batch(data: fileData, file: file)
      } catch {
        return nil
      }
    }

    return nil
  }

  /// This method  gets remaining files at once, and process each file after with the block passed.
  /// Currently called from flush method
  func onRemainingBatches(process: (Batch) -> Void) -> Bool {
    do {
      try orchestrator.getAllFiles(excludingFilesNamed: undeletedFileNames)?.forEach {
        let fileData = try $0.read()
        process(Batch(data: fileData, file: $0))
      }
    } catch {
      return false
    }
    return true
  }

  // MARK: - Accepting batches

  func markBatchAsRead(_ batch: Batch) {
    if !orchestrator.delete(readableFile: batch.file) {
      undeletedFileNames.insert(batch.file.name)
    }
  }
}
