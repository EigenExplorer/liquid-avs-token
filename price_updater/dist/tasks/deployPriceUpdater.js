"use strict";
var __awaiter = (this && this.__awaiter) || function (thisArg, _arguments, P, generator) {
    function adopt(value) { return value instanceof P ? value : new P(function (resolve) { resolve(value); }); }
    return new (P || (P = Promise))(function (resolve, reject) {
        function fulfilled(value) { try { step(generator.next(value)); } catch (e) { reject(e); } }
        function rejected(value) { try { step(generator["throw"](value)); } catch (e) { reject(e); } }
        function step(result) { result.done ? resolve(result.value) : adopt(result.value).then(fulfilled, rejected); }
        step((generator = generator.apply(thisArg, _arguments || [])).next());
    });
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.deployPriceUpdater = void 0;
const forge_1 = require("../../../manager/src/utils/forge");
const utils_1 = require("../../../manager/src/utils");
function deployPriceUpdater() {
    return __awaiter(this, void 0, void 0, function* () {
        const task = "PriceUpdater.s.sol:DeployPriceUpdater";
        const { stdout } = yield (0, utils_1.execAsync)((0, forge_1.forgeCommand)(task, process.env.ADMIN_PUBLIC_KEY, "run()", ""));
        console.log("Price updater contracts deployed");
        console.log(stdout);
    });
}
exports.deployPriceUpdater = deployPriceUpdater;
