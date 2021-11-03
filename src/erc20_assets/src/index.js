import { erc20 } from "../../declarations/erc20";

document.getElementById("clickMeBtn").addEventListener("click", async () => {
  const name = document.getElementById("name").value.toString();
  // Interact with erc20 actor, calling the greet method
  const greeting = await erc20.greet(name);

  document.getElementById("greeting").innerText = greeting;
});
