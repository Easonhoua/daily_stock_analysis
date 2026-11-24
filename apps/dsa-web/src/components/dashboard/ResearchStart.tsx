import { ArrowUpRight, ChartNoAxesCombined, ScanLine, MessagesSquare, Layers3 } from 'lucide-react';
import { Link } from 'react-router-dom';
import { useUiLanguage } from '../../contexts/UiLanguageContext';
export function ResearchStart() {
  const { language } = useUiLanguage();
  const en = language === 'en';
  const paths = [
    { to: '/screening', icon: ScanLine, title: en ? 'Find your next idea' : '发现投资线索', text: en ? 'Explore stocks with your screening criteria.' : '从选股条件出发，缩小值得研究的范围。' },
    { to: '/chat', icon: MessagesSquare, title: en ? 'Ask a deeper question' : '与 AI 深入讨论', text: en ? 'Investigate a company, a sector or a hypothesis.' : '围绕公司、行业或投资假设，展开多轮研究。' },
    { to: '/portfolio', icon: Layers3, title: en ? 'Review your portfolio' : '回到你的持仓', text: en ? 'Connect your research with your holdings.' : '结合已有持仓，让研究与投资决策连接。' },
  ];
  return <div className="research-start"><div className="research-hero"><div className="research-hero-copy"><span className="research-eyebrow">DSA / RESEARCH DESK</span><h2>{en ? <>Your next decision.<br /><em>A clearer perspective.</em></> : <>每一次决策，<br /><em>从看清全局开始。</em></>}</h2><p>{en ? 'Search for a stock above to bring market data, news and AI analysis into one view.' : '在上方搜索股票，将行情、新闻与 AI 分析汇聚到同一份研究报告。'}</p><div className="research-hero-note"><span />{en ? 'A shares · Hong Kong · US markets' : '覆盖 A 股 · 港股 · 美股'}</div></div><div className="research-art" aria-hidden="true"><ChartNoAxesCombined strokeWidth={0.8} /><span>RESEARCH → INSIGHT</span></div></div><div className="research-path-heading"><h3>{en ? 'Make your next move' : '开启你的研究路径'}</h3><span>{en ? 'TOOLS FOR YOUR PROCESS' : '从线索到决策'}</span></div><div className="research-paths">{paths.map(({ to, icon: Icon, title, text }, index) => <Link key={to} to={to} className="research-path"><div className="research-path-top"><Icon size={21} /><span>0{index + 1}</span></div><h3>{title}<ArrowUpRight size={17} /></h3><p>{text}</p></Link>)}</div></div>;
}
