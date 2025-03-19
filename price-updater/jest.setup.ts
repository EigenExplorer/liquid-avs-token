// jest.setup.ts
jest.useFakeTimers();
jest.spyOn(global, 'setTimeout');
jest.spyOn(global, 'setInterval');