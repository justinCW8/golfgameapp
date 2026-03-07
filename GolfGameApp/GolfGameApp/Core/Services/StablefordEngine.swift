import Foundation

struct StablefordHoleScoreInput {
    var gross: Int
    var par: Int
    var handicapStrokes: Int
}

struct StablefordHoleScoreOutput {
    var net: Int
    var points: Int
}

enum StablefordEngine {
    static func scoreHole(_ input: StablefordHoleScoreInput) -> StablefordHoleScoreOutput {
        let net = input.gross - input.handicapStrokes
        let delta = net - input.par

        let points: Int
        if delta <= -3 {
            points = 5
        } else if delta == -2 {
            points = 4
        } else if delta == -1 {
            points = 3
        } else if delta == 0 {
            points = 2
        } else if delta == 1 {
            points = 1
        } else {
            points = 0
        }

        return StablefordHoleScoreOutput(net: net, points: points)
    }
}
