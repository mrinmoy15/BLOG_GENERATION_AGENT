from __future__ import annotations

from langgraph.graph import StateGraph, END

from state import State
from nodes import router, research, orchestrator, worker
from reducer_subgraph import build_reducer_subgraph
from conditionals import route_next, fanout

def main_graph():

    builder = StateGraph(State)

    builder.add_node("router",       router)
    builder.add_node("research",     research)        
    builder.add_node("orchestrator", orchestrator)
    builder.add_node("worker",       worker)
    builder.add_node("reducer",      build_reducer_subgraph())

    builder.set_entry_point("router")
    builder.add_conditional_edges(
        "router", route_next,
        {"research": "research", "orchestrator": "orchestrator"}
    )
    builder.add_edge("research", "orchestrator")
    builder.add_conditional_edges("orchestrator", fanout, ["worker"])
    builder.add_edge("worker", "reducer")
    builder.add_edge("reducer", END)

    return builder.compile()